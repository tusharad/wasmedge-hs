{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : WasmEdge.Function
Description : WasmEdge function types and host function instances
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : stable

Provides types and functions for WebAssembly function types and host function instances:

* 'FunctionType' — parameter and return type signatures
* 'FunctionInstance' — a callable function in WebAssembly or the host
* 'HostFunc' — raw low-level callback interface (@CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal])@)
* 'ToHostFunc' — high-level typeclass allowing normal Haskell functions (e.g. @Int32 -> Int32 -> IO Int32@
  or @CallingFrame -> Word32 -> IO ()@) to be registered directly as host functions without manual value unpacking.
* 'CallingFrame' — execution frame passed to host functions providing access to caller memory and module instances.
-}
module WasmEdge.Function
  ( -- * High-level host functions
    ToHostFunc (..)
  , WasmValType (..)
  , WasmReturn (..)
  , createHostFunction
  , withHostFunction

    -- * Function type
  , FunctionType
  , createFunctionType
  , deleteFunctionType
  , withFunctionType
  , getFunctionTypeParameters
  , getFunctionTypeReturns

    -- * Calling frame
  , CallingFrame (..)
  , callingFrameGetExecutor
  , callingFrameGetModuleInstance
  , callingFrameGetMemoryInstance

    -- * Raw host function callback
  , HostFunc

    -- * Function instance
  , FunctionInstance
  , createFunction
  , deleteFunction
  , withFunction
  , getFunctionType

    -- * Internal / borrowed pointers
  , unsafeFunctionPtr
  , borrowFunction
  , unsafeFunctionTypePtr
  , borrowFunctionType
  , disarmFunction
  ) where

import Control.Exception (bracket, throwIO)
import Control.Monad (forM_)
import Data.Int (Int32, Int64)
import Data.Proxy (Proxy (..))
import Data.Word (Word32, Word64)
import Foreign.Marshal.Utils (copyBytes)
import Foreign.Ptr (FunPtr, Ptr, castPtr, freeHaskellFunPtr, nullPtr, plusPtr)

import WasmEdge.Error
import WasmEdge.Internal.FFI.Basic (c_ResultGen, c_Result_Success)
import WasmEdge.Internal.FFI.Instance
import WasmEdge.Internal.Ownership
  ( BorrowedCtx (..)
  , OwnedCtx
  , disarmOwned
  , finalizeOwned
  , mkOwned
  , withOwned
  )
import WasmEdge.Internal.Storable (withCValTypeArray)
import WasmEdge.Internal.Types
  ( CallingFrameTag
  , ExecutorTag
  , FunctionInstanceTag
  , FunctionTypeTag
  , MemoryInstanceTag
  , ModuleInstanceTag
  )
import WasmEdge.Types
import WasmEdge.Value (encodeVal, peekValArray, peekValTypes, valueSize, withValTypeArray)

-- ---------------------------------------------------------------------------
-- FunctionType
-- ---------------------------------------------------------------------------

-- | A WebAssembly function type describing parameter and return types.
newtype FunctionType = FunctionType (OwnedCtx FunctionTypeTag)

-- | Create a 'FunctionType' from lists of parameter and return types.
createFunctionType :: [ValType] -> [ValType] -> IO FunctionType
createFunctionType params rets =
  withValTypeArray params $ \pArr pLen ->
    withValTypeArray rets $ \rArr rLen -> do
      p <- c_FunctionTypeCreate pArr pLen rArr rLen
      if p == nullPtr
        then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_FunctionTypeCreate returned NULL"
        else FunctionType <$> mkOwned (appFunPtr c_FunctionTypeDelete) p

-- | Delete a 'FunctionType'.
deleteFunctionType :: FunctionType -> IO ()
deleteFunctionType (FunctionType o) = finalizeOwned o

-- | Scoped 'FunctionType'.
withFunctionType :: [ValType] -> [ValType] -> (FunctionType -> IO a) -> IO a
withFunctionType params rets = bracket (createFunctionType params rets) deleteFunctionType

-- | Get the parameter types of a 'FunctionType'.
getFunctionTypeParameters :: FunctionType -> IO [ValType]
getFunctionTypeParameters (FunctionType o) =
  withOwned o $ \p -> do
    len <- c_FunctionTypeGetParametersLength p
    if len == 0
      then pure []
      else withCValTypeArray (fromIntegral len) $ \arr -> do
        _ <- c_FunctionTypeGetParameters p arr len
        peekValTypes arr len

-- | Get the return types of a 'FunctionType'.
getFunctionTypeReturns :: FunctionType -> IO [ValType]
getFunctionTypeReturns (FunctionType o) =
  withOwned o $ \p -> do
    len <- c_FunctionTypeGetReturnsLength p
    if len == 0
      then pure []
      else withCValTypeArray (fromIntegral len) $ \arr -> do
        _ <- c_FunctionTypeGetReturns p arr len
        peekValTypes arr len

-- ---------------------------------------------------------------------------
-- CallingFrame
-- ---------------------------------------------------------------------------

-- | Context passed to a host function callback representing the caller's frame.
newtype CallingFrame = CallingFrame (BorrowedCtx CallingFrameTag)

-- | Get the executor from a 'CallingFrame'.
callingFrameGetExecutor :: CallingFrame -> IO (Ptr ExecutorTag)
callingFrameGetExecutor (CallingFrame (BorrowedCtx p)) =
  c_CallingFrameGetExecutor p

-- | Get the module instance from a 'CallingFrame'.
callingFrameGetModuleInstance :: CallingFrame -> IO (Ptr ModuleInstanceTag)
callingFrameGetModuleInstance (CallingFrame (BorrowedCtx p)) =
  c_CallingFrameGetModuleInstance p

-- | Get the memory instance by index (typically 0) from a 'CallingFrame'.
callingFrameGetMemoryInstance :: CallingFrame -> Word32 -> IO (Ptr MemoryInstanceTag)
callingFrameGetMemoryInstance (CallingFrame (BorrowedCtx p)) =
  c_CallingFrameGetMemoryInstance p

-- ---------------------------------------------------------------------------
-- HostFunc & FunctionInstance
-- ---------------------------------------------------------------------------

-- | Raw low-level Haskell implementation of a host function callable from WebAssembly.
type HostFunc = CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal])

-- | A WebAssembly function instance.
newtype FunctionInstance = FunctionInstance (OwnedCtx FunctionInstanceTag)

-- | Create a host 'FunctionInstance' from a 'FunctionType' and raw Haskell 'HostFunc'.
createFunction :: FunctionType -> HostFunc -> IO FunctionInstance
createFunction (FunctionType ftOwned) hostFn =
  withOwned ftOwned $ \ftPtr -> do
    -- Allocate C callback wrapper
    fptr <- mkHostFuncWrapper $ \_data framePtr paramsPtr pLen returnsPtr _rLen resOutPtr -> do
      vals <- peekValArray (castPtr paramsPtr) pLen
      let frame = CallingFrame (BorrowedCtx framePtr)
      result <- hostFn frame vals
      case result of
        Right retVals -> do
          -- Encode return values into returnsPtr
          forM_ (zip [0 ..] retVals) $ \(i, v) ->
            encodeVal v $ \encodedPtr -> do
              let dst = returnsPtr `plusPtr` (i * valueSize)
              copyBytes dst (castPtr encodedPtr) valueSize
          c_Result_Success resOutPtr
        Left err -> do
          let catCode = case weErrCategory err of
                ErrCategory_WASM -> 0 :: Word32
                ErrCategory_UserDefined -> 1 :: Word32
                ErrCategory_Unknown c -> c
          c_ResultGen resOutPtr catCode (weErrCode err)

    p <- c_FunctionInstanceCreateBinding ftPtr fptr nullPtr 0
    if p == nullPtr
      then do
        freeHaskellFunPtr fptr
        throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_FunctionInstanceCreateBinding returned NULL"
      else
        FunctionInstance
          <$> mkOwned
            ( \ptr -> do
                c_FunctionInstanceDelete `appFunPtr` ptr
                freeHaskellFunPtr fptr
            )
            p

-- | Delete a 'FunctionInstance'.
deleteFunction :: FunctionInstance -> IO ()
deleteFunction (FunctionInstance o) = finalizeOwned o

-- | Scoped 'FunctionInstance' with raw 'HostFunc'.
withFunction :: FunctionType -> HostFunc -> (FunctionInstance -> IO a) -> IO a
withFunction ft hostFn = bracket (createFunction ft hostFn) deleteFunction

-- | Get the 'FunctionType' of a 'FunctionInstance'.
getFunctionType :: FunctionInstance -> IO FunctionType
getFunctionType (FunctionInstance o) =
  withOwned o $ \p -> do
    tp <- c_FunctionInstanceGetFunctionType p
    if tp == nullPtr
      then
        throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_FunctionInstanceGetFunctionType returned NULL"
      else borrowFunctionType tp

-- ---------------------------------------------------------------------------
-- High-Level Typeclass-driven Host Function Registration (ToHostFunc)
-- ---------------------------------------------------------------------------

-- | Typeclass for Haskell values that can be converted to and from a single WebAssembly value.
class WasmValType a where
  toWasmVal :: a -> WasmVal
  fromWasmVal :: WasmVal -> Maybe a
  wasmValType :: Proxy a -> ValType

instance WasmValType Int32 where
  toWasmVal = WasmI32
  fromWasmVal (WasmI32 v) = Just v
  fromWasmVal _ = Nothing
  wasmValType _ = I32

instance WasmValType Word32 where
  toWasmVal = WasmI32 . fromIntegral
  fromWasmVal (WasmI32 v) = Just (fromIntegral v)
  fromWasmVal _ = Nothing
  wasmValType _ = I32

instance WasmValType Int64 where
  toWasmVal = WasmI64
  fromWasmVal (WasmI64 v) = Just v
  fromWasmVal _ = Nothing
  wasmValType _ = I64

instance WasmValType Word64 where
  toWasmVal = WasmI64 . fromIntegral
  fromWasmVal (WasmI64 v) = Just (fromIntegral v)
  fromWasmVal _ = Nothing
  wasmValType _ = I64

instance WasmValType Float where
  toWasmVal = WasmF32
  fromWasmVal (WasmF32 v) = Just v
  fromWasmVal _ = Nothing
  wasmValType _ = F32

instance WasmValType Double where
  toWasmVal = WasmF64
  fromWasmVal (WasmF64 v) = Just v
  fromWasmVal _ = Nothing
  wasmValType _ = F64

instance WasmValType WasmVal where
  toWasmVal = id
  fromWasmVal = Just
  wasmValType _ = I32

-- | Typeclass for host function return values.
class WasmReturn a where
  toWasmReturn :: a -> [WasmVal]
  wasmReturnTypes :: Proxy a -> [ValType]

instance WasmReturn () where
  toWasmReturn () = []
  wasmReturnTypes _ = []

instance WasmReturn Int32 where
  toWasmReturn v = [toWasmVal v]
  wasmReturnTypes _ = [I32]

instance WasmReturn Word32 where
  toWasmReturn v = [toWasmVal v]
  wasmReturnTypes _ = [I32]

instance WasmReturn Int64 where
  toWasmReturn v = [toWasmVal v]
  wasmReturnTypes _ = [I64]

instance WasmReturn Word64 where
  toWasmReturn v = [toWasmVal v]
  wasmReturnTypes _ = [I64]

instance WasmReturn Float where
  toWasmReturn v = [toWasmVal v]
  wasmReturnTypes _ = [F32]

instance WasmReturn Double where
  toWasmReturn v = [toWasmVal v]
  wasmReturnTypes _ = [F64]

instance (WasmValType a, WasmValType b) => WasmReturn (a, b) where
  toWasmReturn (a, b) = [toWasmVal a, toWasmVal b]
  wasmReturnTypes _ = [wasmValType (Proxy :: Proxy a), wasmValType (Proxy :: Proxy b)]

instance (WasmValType a, WasmValType b, WasmValType c) => WasmReturn (a, b, c) where
  toWasmReturn (a, b, c) = [toWasmVal a, toWasmVal b, toWasmVal c]
  wasmReturnTypes _ = [wasmValType (Proxy :: Proxy a), wasmValType (Proxy :: Proxy b), wasmValType (Proxy :: Proxy c)]

{- | Typeclass for functions that can be converted into a WasmEdge host function.

Automatically converts Haskell typed arguments and results, with optional 'CallingFrame'.
-}
class ToHostFunc f where
  toHostFunc :: f -> HostFunc
  hostFuncSignature :: Proxy f -> ([ValType], [ValType])

-- 0 args
instance {-# OVERLAPPABLE #-} (WasmReturn r) => ToHostFunc (IO r) where
  toHostFunc act _frame [] = Right . toWasmReturn <$> act
  toHostFunc _ _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid argument count"))
  hostFuncSignature _ = ([], wasmReturnTypes (Proxy :: Proxy r))

instance {-# OVERLAPPING #-} (WasmReturn r) => ToHostFunc (CallingFrame -> IO r) where
  toHostFunc act frame [] = Right . toWasmReturn <$> act frame
  toHostFunc _ _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid argument count"))
  hostFuncSignature _ = ([], wasmReturnTypes (Proxy :: Proxy r))

-- 1 arg
instance {-# OVERLAPPABLE #-} (WasmValType a, WasmReturn r) => ToHostFunc (a -> IO r) where
  toHostFunc act _frame [va] = case fromWasmVal va of
    Just a -> Right . toWasmReturn <$> act a
    Nothing -> pure (Left (WasmEdgeError ErrCategory_UserDefined 2 "Type mismatch for argument 1"))
  toHostFunc _ _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid argument count"))
  hostFuncSignature _ = ([wasmValType (Proxy :: Proxy a)], wasmReturnTypes (Proxy :: Proxy r))

instance {-# OVERLAPPING #-} (WasmValType a, WasmReturn r) => ToHostFunc (CallingFrame -> a -> IO r) where
  toHostFunc act frame [va] = case fromWasmVal va of
    Just a -> Right . toWasmReturn <$> act frame a
    Nothing -> pure (Left (WasmEdgeError ErrCategory_UserDefined 2 "Type mismatch for argument 1"))
  toHostFunc _ _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid argument count"))
  hostFuncSignature _ = ([wasmValType (Proxy :: Proxy a)], wasmReturnTypes (Proxy :: Proxy r))

-- 2 args
instance {-# OVERLAPPABLE #-} (WasmValType a, WasmValType b, WasmReturn r) => ToHostFunc (a -> b -> IO r) where
  toHostFunc act _frame [va, vb] = case (fromWasmVal va, fromWasmVal vb) of
    (Just a, Just b) -> Right . toWasmReturn <$> act a b
    _ ->
      pure (Left (WasmEdgeError ErrCategory_UserDefined 2 "Type mismatch in arguments"))
  toHostFunc _ _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid argument count"))
  hostFuncSignature _ =
    ( [wasmValType (Proxy :: Proxy a), wasmValType (Proxy :: Proxy b)]
    , wasmReturnTypes (Proxy :: Proxy r)
    )

instance {-# OVERLAPPING #-} (WasmValType a, WasmValType b, WasmReturn r) => ToHostFunc (CallingFrame -> a -> b -> IO r) where
  toHostFunc act frame [va, vb] = case (fromWasmVal va, fromWasmVal vb) of
    (Just a, Just b) -> Right . toWasmReturn <$> act frame a b
    _ ->
      pure (Left (WasmEdgeError ErrCategory_UserDefined 2 "Type mismatch in arguments"))
  toHostFunc _ _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid argument count"))
  hostFuncSignature _ =
    ( [wasmValType (Proxy :: Proxy a), wasmValType (Proxy :: Proxy b)]
    , wasmReturnTypes (Proxy :: Proxy r)
    )

-- 3 args
instance {-# OVERLAPPABLE #-} (WasmValType a, WasmValType b, WasmValType c, WasmReturn r) => ToHostFunc (a -> b -> c -> IO r) where
  toHostFunc act _frame [va, vb, vc] = case (fromWasmVal va, fromWasmVal vb, fromWasmVal vc) of
    (Just a, Just b, Just c) -> Right . toWasmReturn <$> act a b c
    _ ->
      pure (Left (WasmEdgeError ErrCategory_UserDefined 2 "Type mismatch in arguments"))
  toHostFunc _ _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid argument count"))
  hostFuncSignature _ =
    ( [wasmValType (Proxy :: Proxy a), wasmValType (Proxy :: Proxy b), wasmValType (Proxy :: Proxy c)]
    , wasmReturnTypes (Proxy :: Proxy r)
    )

instance
  {-# OVERLAPPING #-}
  (WasmValType a, WasmValType b, WasmValType c, WasmReturn r) =>
  ToHostFunc (CallingFrame -> a -> b -> c -> IO r)
  where
  toHostFunc act frame [va, vb, vc] = case (fromWasmVal va, fromWasmVal vb, fromWasmVal vc) of
    (Just a, Just b, Just c) -> Right . toWasmReturn <$> act frame a b c
    _ ->
      pure (Left (WasmEdgeError ErrCategory_UserDefined 2 "Type mismatch in arguments"))
  toHostFunc _ _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid argument count"))
  hostFuncSignature _ =
    ( [wasmValType (Proxy :: Proxy a), wasmValType (Proxy :: Proxy b), wasmValType (Proxy :: Proxy c)]
    , wasmReturnTypes (Proxy :: Proxy r)
    )

-- 4 args
instance
  {-# OVERLAPPABLE #-}
  (WasmValType a, WasmValType b, WasmValType c, WasmValType d, WasmReturn r) =>
  ToHostFunc (a -> b -> c -> d -> IO r)
  where
  toHostFunc act _frame [va, vb, vc, vd] = case (fromWasmVal va, fromWasmVal vb, fromWasmVal vc, fromWasmVal vd) of
    (Just a, Just b, Just c, Just d) -> Right . toWasmReturn <$> act a b c d
    _ ->
      pure (Left (WasmEdgeError ErrCategory_UserDefined 2 "Type mismatch in arguments"))
  toHostFunc _ _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid argument count"))
  hostFuncSignature _ =
    (
      [ wasmValType (Proxy :: Proxy a)
      , wasmValType (Proxy :: Proxy b)
      , wasmValType (Proxy :: Proxy c)
      , wasmValType (Proxy :: Proxy d)
      ]
    , wasmReturnTypes (Proxy :: Proxy r)
    )

instance
  {-# OVERLAPPING #-}
  (WasmValType a, WasmValType b, WasmValType c, WasmValType d, WasmReturn r) =>
  ToHostFunc (CallingFrame -> a -> b -> c -> d -> IO r)
  where
  toHostFunc act frame [va, vb, vc, vd] = case (fromWasmVal va, fromWasmVal vb, fromWasmVal vc, fromWasmVal vd) of
    (Just a, Just b, Just c, Just d) -> Right . toWasmReturn <$> act frame a b c d
    _ ->
      pure (Left (WasmEdgeError ErrCategory_UserDefined 2 "Type mismatch in arguments"))
  toHostFunc _ _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid argument count"))
  hostFuncSignature _ =
    (
      [ wasmValType (Proxy :: Proxy a)
      , wasmValType (Proxy :: Proxy b)
      , wasmValType (Proxy :: Proxy c)
      , wasmValType (Proxy :: Proxy d)
      ]
    , wasmReturnTypes (Proxy :: Proxy r)
    )

-- | Create a host 'FunctionInstance' automatically inferring its 'FunctionType' from Haskell types.
createHostFunction :: forall f. (ToHostFunc f) => f -> IO FunctionInstance
createHostFunction f = do
  let (params, rets) = hostFuncSignature (Proxy :: Proxy f)
  ft <- createFunctionType params rets
  createFunction ft (toHostFunc f)

-- | Scoped 'FunctionInstance' with automatic signature inference.
withHostFunction :: (ToHostFunc f) => f -> (FunctionInstance -> IO a) -> IO a
withHostFunction f = bracket (createHostFunction f) deleteFunction

-- ---------------------------------------------------------------------------
-- Unsafe / internal pointer helpers
-- ---------------------------------------------------------------------------

-- | Extract the raw pointer of a 'FunctionInstance'.
unsafeFunctionPtr :: FunctionInstance -> IO (Ptr FunctionInstanceTag)
unsafeFunctionPtr (FunctionInstance o) = withOwned o pure

-- | Create a borrowed 'FunctionInstance' from a raw pointer (does not finalize).
borrowFunction :: Ptr FunctionInstanceTag -> IO FunctionInstance
borrowFunction p = FunctionInstance <$> mkOwned (\_ -> pure ()) p

-- | Extract the raw pointer of a 'FunctionType'.
unsafeFunctionTypePtr :: FunctionType -> IO (Ptr FunctionTypeTag)
unsafeFunctionTypePtr (FunctionType o) = withOwned o pure

-- | Create a borrowed 'FunctionType' from a raw pointer (does not finalize).
borrowFunctionType :: Ptr FunctionTypeTag -> IO FunctionType
borrowFunctionType p = FunctionType <$> mkOwned (\_ -> pure ()) p

-- | Disarm finalizer when ownership is transferred to a module instance.
disarmFunction :: FunctionInstance -> IO ()
disarmFunction (FunctionInstance o) = disarmOwned o

-- ---------------------------------------------------------------------------
-- Internal helper
-- ---------------------------------------------------------------------------

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr = mkDeleter

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
