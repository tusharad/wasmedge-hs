-- |
-- Module      : WasmEdge.Global
-- Description : WasmEdge global variable contexts
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : stable
--
-- Provides contexts for WebAssembly global variables:
--
-- * 'GlobalType' — describes the value type and mutability of a global
-- * 'GlobalInstance' — a runtime global variable instance
module WasmEdge.Global
  ( -- * Global type
    GlobalType
  , createGlobalType
  , deleteGlobalType
  , withGlobalType
  , getGlobalTypeValType
  , getGlobalTypeMutability

    -- * Global instance
  , GlobalInstance
  , createGlobal
  , deleteGlobal
  , withGlobal
  , getGlobalType
  , getGlobalValue
  , setGlobalValue

    -- * Internal / borrowed pointers
  , unsafeGlobalPtr
  , borrowGlobal
  , unsafeGlobalTypePtr
  , borrowGlobalType
  , disarmGlobal
  ) where

import Control.Exception (bracket, throwIO)
import Foreign.Ptr
import Data.Word (Word32)

import WasmEdge.Types
import WasmEdge.Error
import WasmEdge.Value (encodeVal, decodeVal, encodeValType, peekValTypes)
import WasmEdge.Internal.Types (GlobalTypeTag, GlobalInstanceTag)
import WasmEdge.Internal.Ownership (OwnedCtx, mkOwned, withOwned, finalizeOwned, disarmOwned)
import WasmEdge.Internal.Storable (allocaCValType, allocaCValue, allocaCResult)
import WasmEdge.Internal.Utils (checkResult)
import WasmEdge.Internal.FFI.Instance

-- ---------------------------------------------------------------------------
-- GlobalType
-- ---------------------------------------------------------------------------

-- | A WebAssembly global type context, describing its type and mutability.
newtype GlobalType = GlobalType (OwnedCtx GlobalTypeTag)

-- | Create a 'GlobalType' with the specified 'ValType' and 'Mutability'.
createGlobalType :: ValType -> Mutability -> IO GlobalType
createGlobalType vt mut =
  encodeValType vt $ \vtPtr -> do
    let mutCode = case mut of
          Const -> 0 :: Word32
          Var   -> 1 :: Word32
    p <- c_GlobalTypeCreate vtPtr mutCode
    if p == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_GlobalTypeCreate returned NULL"
      else GlobalType <$> mkOwned (appFunPtr c_GlobalTypeDelete) p

-- | Delete a 'GlobalType' context.
deleteGlobalType :: GlobalType -> IO ()
deleteGlobalType (GlobalType o) = finalizeOwned o

-- | Scoped 'GlobalType' context.
withGlobalType :: ValType -> Mutability -> (GlobalType -> IO a) -> IO a
withGlobalType vt mut = bracket (createGlobalType vt mut) deleteGlobalType

-- | Retrieve the 'ValType' of a 'GlobalType'.
getGlobalTypeValType :: GlobalType -> IO ValType
getGlobalTypeValType (GlobalType o) =
  withOwned o $ \p ->
  allocaCValType $ \vtPtr -> do
    c_GlobalTypeGetValType p vtPtr
    types <- peekValTypes vtPtr 1
    case types of
      (t:_) -> pure t
      []    -> pure I32

-- | Retrieve the 'Mutability' of a 'GlobalType'.
getGlobalTypeMutability :: GlobalType -> IO Mutability
getGlobalTypeMutability (GlobalType o) =
  withOwned o $ \p -> do
    m <- c_GlobalTypeGetMutability p
    pure (if m == 0 then Const else Var)

-- ---------------------------------------------------------------------------
-- GlobalInstance
-- ---------------------------------------------------------------------------

-- | A runtime WebAssembly global variable instance.
newtype GlobalInstance = GlobalInstance (OwnedCtx GlobalInstanceTag)

-- | Create a 'GlobalInstance' with the given type and initial value.
createGlobal :: GlobalType -> WasmVal -> IO GlobalInstance
createGlobal (GlobalType gtOwned) val =
  withOwned gtOwned $ \gtPtr ->
  encodeVal val $ \valPtr -> do
    p <- c_GlobalInstanceCreate gtPtr valPtr
    if p == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_GlobalInstanceCreate returned NULL"
      else GlobalInstance <$> mkOwned (appFunPtr c_GlobalInstanceDelete) p

-- | Delete a 'GlobalInstance'.
deleteGlobal :: GlobalInstance -> IO ()
deleteGlobal (GlobalInstance o) = finalizeOwned o

-- | Scoped 'GlobalInstance'.
withGlobal :: GlobalType -> WasmVal -> (GlobalInstance -> IO a) -> IO a
withGlobal gt val = bracket (createGlobal gt val) deleteGlobal

-- | Get the 'GlobalType' of a 'GlobalInstance'.
-- Note: the returned 'GlobalType' borrows the type context from the instance.
getGlobalType :: GlobalInstance -> IO GlobalType
getGlobalType (GlobalInstance o) =
  withOwned o $ \p -> do
    tp <- c_GlobalInstanceGetGlobalType p
    if tp == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_GlobalInstanceGetGlobalType returned NULL"
      else borrowGlobalType tp

-- | Get the current value of a global variable.
getGlobalValue :: GlobalInstance -> IO WasmVal
getGlobalValue (GlobalInstance o) =
  withOwned o $ \p ->
  allocaCValue $ \valPtr -> do
    c_GlobalInstanceGetValue valPtr p
    decodeVal valPtr

-- | Set a new value for a mutable global variable.
-- Fails with a 'WasmEdgeError' if the global is immutable or type mismatches.
setGlobalValue :: GlobalInstance -> WasmVal -> IO (WasmResult ())
setGlobalValue (GlobalInstance o) val =
  withOwned o $ \p ->
  encodeVal val $ \valPtr ->
  allocaCResult $ \resPtr -> do
    c_GlobalInstanceSetValue resPtr p valPtr
    checkResult resPtr

-- ---------------------------------------------------------------------------
-- Unsafe / internal pointer helpers
-- ---------------------------------------------------------------------------

-- | Extract the raw pointer of a 'GlobalInstance'.
unsafeGlobalPtr :: GlobalInstance -> IO (Ptr GlobalInstanceTag)
unsafeGlobalPtr (GlobalInstance o) = withOwned o pure

-- | Create a borrowed 'GlobalInstance' from a raw pointer (does not finalize).
borrowGlobal :: Ptr GlobalInstanceTag -> IO GlobalInstance
borrowGlobal p = GlobalInstance <$> mkOwned (\_ -> pure ()) p

-- | Extract the raw pointer of a 'GlobalType'.
unsafeGlobalTypePtr :: GlobalType -> IO (Ptr GlobalTypeTag)
unsafeGlobalTypePtr (GlobalType o) = withOwned o pure

-- | Create a borrowed 'GlobalType' from a raw pointer (does not finalize).
borrowGlobalType :: Ptr GlobalTypeTag -> IO GlobalType
borrowGlobalType p = GlobalType <$> mkOwned (\_ -> pure ()) p

-- | Disarm finalizer when ownership is transferred to a module instance.
disarmGlobal :: GlobalInstance -> IO ()
disarmGlobal (GlobalInstance o) = disarmOwned o

-- ---------------------------------------------------------------------------
-- Internal helper
-- ---------------------------------------------------------------------------

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr fp p = mkDeleter fp p

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
