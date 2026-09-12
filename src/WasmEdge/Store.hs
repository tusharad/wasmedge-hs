-- |
-- Module      : WasmEdge.Store
-- Description : WasmEdge store context
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
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

import Control.Exception (bracket, throwIO)
import Data.Text         (Text)
import Foreign.Ptr
import WasmEdge.Error
import WasmEdge.Internal.Types
import WasmEdge.Internal.Ownership
import WasmEdge.Internal.Storable
import WasmEdge.Internal.FFI.Execution
import WasmEdge.Internal.Utils (withWasmString, peekWasmString)

newtype Store = Store (OwnedCtx StoreTag)

createStore :: IO Store
createStore = do
  p <- c_StoreCreate
  if p == nullPtr
    then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_StoreCreate returned NULL"
    else Store <$> mkOwned (appFunPtr c_StoreDelete) p

deleteStore :: Store -> IO ()
deleteStore (Store o) = withOwned o (appFunPtr c_StoreDelete)

withStore :: (Store -> IO a) -> IO a
withStore = bracket createStore deleteStore

findModule :: Store -> Text -> IO (Maybe ())  -- returns ModuleInstance (placeholder)
findModule (Store o) modName =
  withOwned o $ \p ->
  withWasmString modName $ \nameStr -> do
    mp <- c_StoreFindModule p nameStr
    pure (if mp == nullPtr then Nothing else Just ())

listModules :: Store -> IO [Text]
listModules (Store o) =
  withOwned o $ \p -> do
    n <- c_StoreListModuleLength p
    pure []  -- stub

-- Internal: get raw pointer (borrowed)
unsafeStorePtr :: Store -> IO (Ptr StoreTag)
unsafeStorePtr (Store o) = withOwned o pure

-- Create a borrowed Store from a raw pointer (from VM)
borrowStore :: Ptr StoreTag -> IO Store
borrowStore p = Store <$> mkOwned (\_ -> pure ()) p  -- no-op finalizer

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr fp p = mkDeleter fp p
foreign import ccall "dynamic" mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
