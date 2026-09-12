-- |
-- Module      : WasmEdge.Function
-- Description : WasmEdge function types and host function instances
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : stable
--
-- Provides types for WebAssembly function types and host function instances:
--
-- * 'FunctionType' — parameter and return type signatures
-- * 'FunctionInstance' — a function that can be called from WASM or the host
-- * 'HostFunc' — Haskell callback implementation callable by WASM guest code
-- * 'CallingFrame' — context passed to host functions providing access to
--   caller module and memory instances
module WasmEdge.Function
  ( -- * Function type
    FunctionType
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

    -- * Host function callback
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

import Control.Exception     (bracket, throwIO)
import Control.Monad         (forM_)
import Foreign.C             (CBool (..))
import Foreign.Marshal.Alloc (alloca, allocaBytes)
import Foreign.Marshal.Utils (copyBytes)
import Foreign.Ptr           (Ptr, FunPtr, nullPtr, castPtr, plusPtr, freeHaskellFunPtr)
import Foreign.Storable      (peek, poke)
import Data.Word             (Word32, Word64)

import WasmEdge.Types
import WasmEdge.Error
import WasmEdge.Value        (encodeVal, decodeVal, withValTypeArray, peekValTypes,
                              peekValArray, valueSize)
import WasmEdge.Internal.Types     (FunctionTypeTag, FunctionInstanceTag,
                              CallingFrameTag, ExecutorTag, ModuleInstanceTag,
                              MemoryInstanceTag)
import WasmEdge.Internal.Ownership (OwnedCtx, BorrowedCtx (..), mkOwned, withOwned, finalizeOwned, disarmOwned)
import WasmEdge.Internal.Storable  (allocaCValType, allocaCValue, allocaCResult,
                              CResult_, withCValTypeArray, valTypeSize)
import WasmEdge.Internal.FFI.Basic (c_Result_Success, c_Result_Fail, c_ResultGen)
import WasmEdge.Internal.FFI.Instance

-- ---------------------------------------------------------------------------
-- FunctionType
-- ---------------------------------------------------------------------------

-- | Signature of a WebAssembly function (parameters and return types).
newtype FunctionType = FunctionType (OwnedCtx FunctionTypeTag)

-- | Create a 'FunctionType' from lists of parameter and return types.
createFunctionType :: [ValType] -> [ValType] -> IO FunctionType
createFunctionType params rets =
  withValTypeArray params $ \pArr pLen ->
  withValTypeArray rets   $ \rArr rLen -> do
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
        c_FunctionTypeGetParameters p arr len
        peekValTypes arr len

-- | Get the return types of a 'FunctionType'.
getFunctionTypeReturns :: FunctionType -> IO [ValType]
getFunctionTypeReturns (FunctionType o) =
  withOwned o $ \p -> do
    len <- c_FunctionTypeGetReturnsLength p
    if len == 0
      then pure []
      else withCValTypeArray (fromIntegral len) $ \arr -> do
        c_FunctionTypeGetReturns p arr len
        peekValTypes arr len

-- ---------------------------------------------------------------------------
-- CallingFrame
-- ---------------------------------------------------------------------------

-- | Context passed to host function callbacks.
newtype CallingFrame = CallingFrame (BorrowedCtx CallingFrameTag)

-- | Get the executor context from a calling frame.
callingFrameGetExecutor :: CallingFrame -> IO (Ptr ExecutorTag)
callingFrameGetExecutor (CallingFrame (BorrowedCtx p)) =
  c_CallingFrameGetExecutor p

-- | Get the caller's module instance from a calling frame.
callingFrameGetModuleInstance :: CallingFrame -> IO (Ptr ModuleInstanceTag)
callingFrameGetModuleInstance (CallingFrame (BorrowedCtx p)) =
  c_CallingFrameGetModuleInstance p

-- | Get a memory instance by index (usually 0) from the caller's module.
callingFrameGetMemoryInstance :: CallingFrame -> Word32 -> IO (Ptr MemoryInstanceTag)
callingFrameGetMemoryInstance (CallingFrame (BorrowedCtx p)) idx =
  c_CallingFrameGetMemoryInstance p idx

-- ---------------------------------------------------------------------------
-- HostFunc & FunctionInstance
-- ---------------------------------------------------------------------------

-- | Haskell implementation of a host function callable from WebAssembly.
type HostFunc = CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal])

-- | A WebAssembly function instance.
newtype FunctionInstance = FunctionInstance (OwnedCtx FunctionInstanceTag)

-- | Create a host 'FunctionInstance' from a 'FunctionType' and Haskell 'HostFunc'.
-- Both the function instance and the Haskell callback wrapper are cleaned up
-- when the 'FunctionInstance' is deleted.
createFunction :: FunctionType -> HostFunc -> IO FunctionInstance
createFunction (FunctionType ftOwned) hostFn =
  withOwned ftOwned $ \ftPtr -> do
    -- Allocate C callback wrapper
    fptr <- mkHostFuncWrapper $ \_data framePtr paramsPtr pLen returnsPtr rLen resOutPtr -> do
      vals <- peekValArray (castPtr paramsPtr) pLen
      let frame = CallingFrame (BorrowedCtx framePtr)
      result <- hostFn frame vals
      case result of
        Right retVals -> do
          -- Encode return values into returnsPtr
          forM_ (zip [0..] retVals) $ \(i, v) ->
            encodeVal v $ \encodedPtr -> do
              let dst = returnsPtr `plusPtr` (i * valueSize)
              copyBytes dst (castPtr encodedPtr) valueSize
          c_Result_Success resOutPtr
        Left err -> do
          let catCode = case weErrCategory err of
                ErrCategory_WASM        -> 0 :: Word32
                ErrCategory_UserDefined -> 1 :: Word32
                ErrCategory_Unknown c   -> c
          c_ResultGen resOutPtr catCode (weErrCode err)

    p <- c_FunctionInstanceCreateBinding ftPtr fptr nullPtr 0
    if p == nullPtr
      then do
        freeHaskellFunPtr fptr
        throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_FunctionInstanceCreateBinding returned NULL"
      else FunctionInstance <$> mkOwned (\ptr -> do
             c_FunctionInstanceDelete `appFunPtr` ptr
             freeHaskellFunPtr fptr
           ) p

-- | Delete a 'FunctionInstance'.
deleteFunction :: FunctionInstance -> IO ()
deleteFunction (FunctionInstance o) = finalizeOwned o

-- | Scoped 'FunctionInstance'.
withFunction :: FunctionType -> HostFunc -> (FunctionInstance -> IO a) -> IO a
withFunction ft hostFn = bracket (createFunction ft hostFn) deleteFunction

-- | Get the 'FunctionType' of a 'FunctionInstance'.
getFunctionType :: FunctionInstance -> IO FunctionType
getFunctionType (FunctionInstance o) =
  withOwned o $ \p -> do
    tp <- c_FunctionInstanceGetFunctionType p
    if tp == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_FunctionInstanceGetFunctionType returned NULL"
      else borrowFunctionType tp

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
appFunPtr fp p = mkDeleter fp p

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
