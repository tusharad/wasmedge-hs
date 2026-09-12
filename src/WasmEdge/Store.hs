-- |
-- Module      : WasmEdge.Store
-- Description : WasmEdge store context
-- Copyright   : (c) 2026 Tushar Adhatrao
-- License     : MIT
-- Stability   : stable
module WasmEdge.Store
  ( Store
  , createStore
  , deleteStore
  , withStore
  , findModule
  , listModules
  -- Internal
  , unsafeStorePtr
  , borrowStore
  ) where

import Control.Exception     (bracket, throwIO)
import Control.Monad         (forM)
import Data.Text             (Text)
import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.Ptr           (Ptr, FunPtr, nullPtr, plusPtr)
import WasmEdge.Error
import WasmEdge.Module       (ModuleInstance, borrowModule)
import WasmEdge.Internal.Types
import WasmEdge.Internal.Ownership
import WasmEdge.Internal.Storable  (stringSize)
import WasmEdge.Internal.FFI.Execution
import WasmEdge.Internal.Utils     (withWasmString, peekWasmString)

-- | WebAssembly runtime store context for module instances and exported definitions.
newtype Store = Store (OwnedCtx StoreTag)

-- | Create a new runtime 'Store'.
createStore :: IO Store
createStore = do
  p <- c_StoreCreate
  if p == nullPtr
    then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_StoreCreate returned NULL"
    else Store <$> mkOwned (appFunPtr c_StoreDelete) p

-- | Delete a runtime 'Store'.
deleteStore :: Store -> IO ()
deleteStore (Store o) = finalizeOwned o

-- | Scoped runtime 'Store'.
withStore :: (Store -> IO a) -> IO a
withStore = bracket createStore deleteStore

-- | Find an exported module by name in the store.
findModule :: Store -> Text -> IO (Maybe ModuleInstance)
findModule (Store o) modName =
  withOwned o $ \p ->
  withWasmString modName $ \nameStr -> do
    mp <- c_StoreFindModule p nameStr
    if mp == nullPtr
      then pure Nothing
      else Just <$> borrowModule mp

-- | List all registered module names in the store.
listModules :: Store -> IO [Text]
listModules (Store o) =
  withOwned o $ \p -> do
    n <- c_StoreListModuleLength p
    if n == 0
      then pure []
      else allocaBytes (fromIntegral n * stringSize) $ \arr -> do
        _ <- c_StoreListModule p arr n
        forM [0 .. fromIntegral n - 1] $ \i -> do
          let ptr = arr `plusPtr` (i * stringSize)
          peekWasmString ptr

-- | Extract the raw pointer of a 'Store'.
unsafeStorePtr :: Store -> IO (Ptr StoreTag)
unsafeStorePtr (Store o) = withOwned o pure

-- | Create a borrowed 'Store' from a raw pointer (does not finalize).
borrowStore :: Ptr StoreTag -> IO Store
borrowStore p = Store <$> mkOwned (\_ -> pure ()) p  -- no-op finalizer

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr fp p = mkDeleter fp p
foreign import ccall "dynamic" mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
