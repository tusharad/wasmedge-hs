-- |
-- Module      : WasmEdge.Plugin
-- Description : WasmEdge plugin discovery, loading, and module instantiation
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : stable
--
-- The WasmEdge plugin system allows loading native dynamic libraries that provide
-- custom host modules (such as WASI-NN, WASI-Crypto, etc.).
module WasmEdge.Plugin
  ( -- * Plugin discovery & loading
    loadPluginsWithDefaultPaths
  , loadPluginFromPath
  , listPlugins
  , findPlugin

    -- * Plugin operations
  , Plugin (..)
  , getPluginName
  , listPluginModules
  , createPluginModule

    -- * WASI-NN specific initialization
  , initWASINN

    -- * Internal / borrowed pointers
  , unsafePluginPtr
  , borrowPlugin
  ) where

import Control.Monad         (forM)
import Data.Text             (Text)
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString    as BS
import Foreign.C.String      (CString, withCString)
import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.Marshal.Array (withArray)
import Foreign.Ptr           (Ptr, nullPtr, plusPtr)
import Data.Word             (Word32)

import WasmEdge.Module       (ModuleInstance (..), borrowModule)
import WasmEdge.Internal.Types     (PluginTag)
import WasmEdge.Internal.Ownership (BorrowedCtx (..))
import WasmEdge.Internal.Storable  (CString_, stringSize, allocaCString)
import WasmEdge.Internal.Utils     (withWasmString, peekWasmString)
import WasmEdge.Internal.FFI.Plugin

-- ---------------------------------------------------------------------------
-- Plugin discovery
-- ---------------------------------------------------------------------------

-- | Load all plugins from the default search paths (e.g., @$WASMEDGE_PLUGIN_PATH@).
loadPluginsWithDefaultPaths :: IO ()
loadPluginsWithDefaultPaths = c_PluginLoadWithDefaultPaths

-- | Load a specific plugin library from a given file path.
loadPluginFromPath :: FilePath -> IO ()
loadPluginFromPath path = withCString path c_PluginLoadFromPath

-- | List names of all currently loaded plugins.
listPlugins :: IO [Text]
listPlugins = do
  len <- c_PluginListPluginsLength
  if len == 0
    then pure []
    else allocaBytes (fromIntegral len * stringSize) $ \arr -> do
      c_PluginListPlugins arr len
      peekStringList arr len

-- ---------------------------------------------------------------------------
-- Plugin context
-- ---------------------------------------------------------------------------

-- | A loaded WasmEdge plugin.
-- Plugins are managed by the global runtime and referenced as borrowed contexts.
newtype Plugin = Plugin (BorrowedCtx PluginTag)
  deriving stock (Eq)

-- | Find a loaded plugin by name. Returns 'Nothing' if not loaded.
findPlugin :: Text -> IO (Maybe Plugin)
findPlugin name =
  withWasmString name $ \namePtr -> do
    p <- c_PluginFind namePtr
    if p == nullPtr
      then pure Nothing
      else pure (Just (Plugin (BorrowedCtx p)))

-- | Get the name of a plugin.
getPluginName :: Plugin -> IO Text
getPluginName (Plugin (BorrowedCtx p)) =
  allocaCString $ \namePtr -> do
    c_PluginGetPluginName namePtr p
    peekWasmString namePtr

-- | List all module names provided by this plugin.
listPluginModules :: Plugin -> IO [Text]
listPluginModules (Plugin (BorrowedCtx p)) = do
  len <- c_PluginListModuleLength p
  if len == 0
    then pure []
    else allocaBytes (fromIntegral len * stringSize) $ \arr -> do
      c_PluginListModule p arr len
      peekStringList arr len

-- | Create a 'ModuleInstance' provided by this plugin under the given module name.
createPluginModule :: Plugin -> Text -> IO (Maybe ModuleInstance)
createPluginModule (Plugin (BorrowedCtx p)) modName =
  withWasmString modName $ \namePtr -> do
    mPtr <- c_PluginCreateModule p namePtr
    if mPtr == nullPtr
      then pure Nothing
      else Just <$> borrowModule mPtr

-- | Initialize WASI-NN with pre-loaded neural network model paths.
initWASINN :: [Text] -> IO ()
initWASINN models =
  withCStrings models $ \count arrPtr ->
    c_PluginInitWASINN arrPtr count

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- | Extract the raw pointer of a 'Plugin'.
unsafePluginPtr :: Plugin -> Ptr PluginTag
unsafePluginPtr (Plugin (BorrowedCtx p)) = p

-- | Construct a borrowed 'Plugin' from a raw pointer.
borrowPlugin :: Ptr PluginTag -> IO Plugin
borrowPlugin p = pure (Plugin (BorrowedCtx p))

peekStringList :: Ptr CString_ -> Word32 -> IO [Text]
peekStringList arr len =
  forM [0 .. fromIntegral len - 1] $ \i -> do
    let ptr = arr `plusPtr` (i * stringSize)
    peekWasmString ptr

withCStrings :: [Text] -> (Word32 -> Ptr CString -> IO a) -> IO a
withCStrings texts action = go texts []
  where
    go [] acc =
      withArray (reverse acc) $ \ptr ->
        action (fromIntegral (length texts)) ptr
    go (t:ts) acc =
      BS.useAsCString (TE.encodeUtf8 t) $ \cstr ->
        go ts (cstr : acc)
