-- |
-- Module      : WasmEdge.Module
-- Description : WasmEdge module instances, host modules, and WASI
-- Copyright   : (c) 2026 Tushar Adhatrao
-- License     : MIT
-- Stability   : stable
--
-- Provides types and functions for managing WebAssembly module instances:
--
-- * 'ModuleInstance' — an instantiated WASM module or a custom host module
-- * Host module construction via 'buildHostModule' or 'addFunction'/'addMemory'/etc.
-- * Full WASI initialization and exit code querying via 'createWASIModule'
module WasmEdge.Module
  ( -- * Module instance
    ModuleInstance (..)
  , createHostModule
  , createWASIModule
  , deleteModuleInstance
  , withHostModule
  , withWASIModule

    -- * WASI functions
  , initWASI
  , getWASIExitCode

    -- * Queries
  , getModuleName
  , findFunction
  , findTable
  , findMemory
  , findGlobal
  , findTag
  , listFunctions
  , listTables
  , listMemories
  , listGlobals
  , listTags

    -- * Population (building host modules)
  , addFunction
  , addTable
  , addMemory
  , addGlobal

    -- * Builder pattern
  , ModuleBuilder
  , buildHostModule
  , builderAddFunction
  , builderAddHostFunc
  , builderAddTable
  , builderAddMemory
  , builderAddGlobal

    -- * Internal / borrowed pointers
  , unsafeModulePtr
  , borrowModule
  ) where

import Control.Exception     (bracket, throwIO)
import Control.Monad         (forM)
import Data.Text             (Text)
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString    as BS
import Foreign.C.String      (CString)
import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.Marshal.Array (withArray)
import Foreign.Ptr           (Ptr, FunPtr, nullPtr, plusPtr)
import Data.Word             (Word32)

import WasmEdge.Error
import WasmEdge.Function     ( FunctionInstance, borrowFunction, unsafeFunctionPtr, disarmFunction
                             , ToHostFunc, createHostFunction
                             )
import WasmEdge.Table        (TableInstance, borrowTable, unsafeTablePtr, disarmTable)
import WasmEdge.Memory       (MemoryInstance, borrowMemory, unsafeMemoryPtr, disarmMemory)
import WasmEdge.Global       (GlobalInstance, borrowGlobal, unsafeGlobalPtr, disarmGlobal)
import WasmEdge.Tag          (TagInstance, borrowTagInstance)
import WasmEdge.Internal.Types     (ModuleInstanceTag)
import WasmEdge.Internal.Ownership (OwnedCtx, mkOwned, withOwned, finalizeOwned)
import WasmEdge.Internal.Storable  (CString_, stringSize, allocaCString)
import WasmEdge.Internal.Utils     (withWasmString, peekWasmString)
import WasmEdge.Internal.FFI.Instance

-- ---------------------------------------------------------------------------
-- ModuleInstance
-- ---------------------------------------------------------------------------

-- | A WebAssembly module instance (guest module or host module).
newtype ModuleInstance = ModuleInstance (OwnedCtx ModuleInstanceTag)

-- | Create an empty host module instance with the given module name.
createHostModule :: Text -> IO ModuleInstance
createHostModule name =
  withWasmString name $ \namePtr -> do
    p <- c_ModuleInstanceCreate namePtr
    if p == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_ModuleInstanceCreate returned NULL"
      else ModuleInstance <$> mkOwned (appFunPtr c_ModuleInstanceDelete) p

-- | Delete a 'ModuleInstance'.
deleteModuleInstance :: ModuleInstance -> IO ()
deleteModuleInstance (ModuleInstance o) = finalizeOwned o

-- | Scoped host module instance.
withHostModule :: Text -> (ModuleInstance -> IO a) -> IO a
withHostModule name = bracket (createHostModule name) deleteModuleInstance

-- ---------------------------------------------------------------------------
-- WASI
-- ---------------------------------------------------------------------------

-- | Create a WASI module instance initialized with arguments, environment variables,
-- and preopened directory mappings.
--
-- * @args@: command-line arguments (e.g., @[\"prog\", \"arg1\"]@)
-- * @envs@: environment variables in @"KEY=VALUE"@ format
-- * @preopens@: directory mappings in @"guest_dir:host_dir"@ format
createWASIModule :: [Text] -> [Text] -> [Text] -> IO ModuleInstance
createWASIModule args envs preopens =
  withCStrings args $ \argc cArgs ->
  withCStrings envs $ \envLen cEnvs ->
  withCStrings preopens $ \preLen cPreopens -> do
    p <- c_ModuleInstanceCreateWASI cArgs argc cEnvs envLen cPreopens preLen
    if p == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_ModuleInstanceCreateWASI returned NULL"
      else ModuleInstance <$> mkOwned (appFunPtr c_ModuleInstanceDelete) p

-- | Scoped WASI module instance.
withWASIModule :: [Text] -> [Text] -> [Text] -> (ModuleInstance -> IO a) -> IO a
withWASIModule args envs preopens =
  bracket (createWASIModule args envs preopens) deleteModuleInstance

-- | Re-initialize WASI parameters on an existing WASI module instance.
initWASI :: ModuleInstance -> [Text] -> [Text] -> [Text] -> IO ()
initWASI (ModuleInstance o) args envs preopens =
  withOwned o $ \p ->
  withCStrings args $ \argc cArgs ->
  withCStrings envs $ \envLen cEnvs ->
  withCStrings preopens $ \preLen cPreopens ->
    c_ModuleInstanceInitWASI p cArgs argc cEnvs envLen cPreopens preLen

-- | Get the exit code from WASI execution.
getWASIExitCode :: ModuleInstance -> IO Word32
getWASIExitCode (ModuleInstance o) =
  withOwned o c_ModuleInstanceWASIGetExitCode

-- ---------------------------------------------------------------------------
-- Queries
-- ---------------------------------------------------------------------------

-- | Get the exported module name.
getModuleName :: ModuleInstance -> IO Text
getModuleName (ModuleInstance o) =
  withOwned o $ \p ->
  allocaCString $ \strPtr -> do
    c_ModuleInstanceGetModuleName strPtr p
    peekWasmString strPtr

-- | Find an exported function by name.
findFunction :: ModuleInstance -> Text -> IO (Maybe FunctionInstance)
findFunction (ModuleInstance o) name =
  withOwned o $ \p ->
  withWasmString name $ \namePtr -> do
    fp <- c_ModuleInstanceFindFunction p namePtr
    if fp == nullPtr
      then pure Nothing
      else Just <$> borrowFunction fp

-- | Find an exported table by name.
findTable :: ModuleInstance -> Text -> IO (Maybe TableInstance)
findTable (ModuleInstance o) name =
  withOwned o $ \p ->
  withWasmString name $ \namePtr -> do
    tp <- c_ModuleInstanceFindTable p namePtr
    if tp == nullPtr
      then pure Nothing
      else Just <$> borrowTable tp

-- | Find an exported memory by name.
findMemory :: ModuleInstance -> Text -> IO (Maybe MemoryInstance)
findMemory (ModuleInstance o) name =
  withOwned o $ \p ->
  withWasmString name $ \namePtr -> do
    mp <- c_ModuleInstanceFindMemory p namePtr
    if mp == nullPtr
      then pure Nothing
      else Just <$> borrowMemory mp

-- | Find an exported global by name.
findGlobal :: ModuleInstance -> Text -> IO (Maybe GlobalInstance)
findGlobal (ModuleInstance o) name =
  withOwned o $ \p ->
  withWasmString name $ \namePtr -> do
    gp <- c_ModuleInstanceFindGlobal p namePtr
    if gp == nullPtr
      then pure Nothing
      else Just <$> borrowGlobal gp

-- | Find an exported exception tag by name (0.18+).
findTag :: ModuleInstance -> Text -> IO (Maybe TagInstance)
findTag (ModuleInstance o) name =
  withOwned o $ \p ->
  withWasmString name $ \namePtr -> do
    tp <- c_ModuleInstanceFindTag p namePtr
    if tp == nullPtr
      then pure Nothing
      else Just <$> borrowTagInstance tp

-- | List all exported function names.
listFunctions :: ModuleInstance -> IO [Text]
listFunctions (ModuleInstance o) =
  withOwned o $ \p -> do
    len <- c_ModuleInstanceListFunctionLength p
    if len == 0
      then pure []
      else allocaBytes (fromIntegral len * stringSize) $ \arr -> do
        c_ModuleInstanceListFunction p arr len
        peekStringList arr len

-- | List all exported table names.
listTables :: ModuleInstance -> IO [Text]
listTables (ModuleInstance o) =
  withOwned o $ \p -> do
    len <- c_ModuleInstanceListTableLength p
    if len == 0
      then pure []
      else allocaBytes (fromIntegral len * stringSize) $ \arr -> do
        c_ModuleInstanceListTable p arr len
        peekStringList arr len

-- | List all exported memory names.
listMemories :: ModuleInstance -> IO [Text]
listMemories (ModuleInstance o) =
  withOwned o $ \p -> do
    len <- c_ModuleInstanceListMemoryLength p
    if len == 0
      then pure []
      else allocaBytes (fromIntegral len * stringSize) $ \arr -> do
        c_ModuleInstanceListMemory p arr len
        peekStringList arr len

-- | List all exported global names.
listGlobals :: ModuleInstance -> IO [Text]
listGlobals (ModuleInstance o) =
  withOwned o $ \p -> do
    len <- c_ModuleInstanceListGlobalLength p
    if len == 0
      then pure []
      else allocaBytes (fromIntegral len * stringSize) $ \arr -> do
        c_ModuleInstanceListGlobal p arr len
        peekStringList arr len

-- | List all exported tag names (0.18+).
listTags :: ModuleInstance -> IO [Text]
listTags (ModuleInstance o) =
  withOwned o $ \p -> do
    len <- c_ModuleInstanceListTagLength p
    if len == 0
      then pure []
      else allocaBytes (fromIntegral len * stringSize) $ \arr -> do
        c_ModuleInstanceListTag p arr len
        peekStringList arr len

-- ---------------------------------------------------------------------------
-- Add elements to host module
-- ---------------------------------------------------------------------------

-- | Add a 'FunctionInstance' to a host module under the given export name.
-- Moves ownership of the function instance into the module.
addFunction :: ModuleInstance -> Text -> FunctionInstance -> IO ()
addFunction (ModuleInstance o) name fn =
  withOwned o $ \p ->
  withWasmString name $ \namePtr -> do
    fnPtr <- unsafeFunctionPtr fn
    c_ModuleInstanceAddFunction p namePtr fnPtr
    disarmFunction fn

-- | Add a 'TableInstance' to a host module under the given export name.
-- Moves ownership of the table instance into the module.
addTable :: ModuleInstance -> Text -> TableInstance -> IO ()
addTable (ModuleInstance o) name tbl =
  withOwned o $ \p ->
  withWasmString name $ \namePtr -> do
    tblPtr <- unsafeTablePtr tbl
    c_ModuleInstanceAddTable p namePtr tblPtr
    disarmTable tbl

-- | Add a 'MemoryInstance' to a host module under the given export name.
-- Moves ownership of the memory instance into the module.
addMemory :: ModuleInstance -> Text -> MemoryInstance -> IO ()
addMemory (ModuleInstance o) name mem =
  withOwned o $ \p ->
  withWasmString name $ \namePtr -> do
    memPtr <- unsafeMemoryPtr mem
    c_ModuleInstanceAddMemory p namePtr memPtr
    disarmMemory mem

-- | Add a 'GlobalInstance' to a host module under the given export name.
-- Moves ownership of the global instance into the module.
addGlobal :: ModuleInstance -> Text -> GlobalInstance -> IO ()
addGlobal (ModuleInstance o) name g =
  withOwned o $ \p ->
  withWasmString name $ \namePtr -> do
    gPtr <- unsafeGlobalPtr g
    c_ModuleInstanceAddGlobal p namePtr gPtr
    disarmGlobal g

-- ---------------------------------------------------------------------------
-- Builder pattern
-- ---------------------------------------------------------------------------

-- | A builder for incrementally assembling a host module.
newtype ModuleBuilder = ModuleBuilder ModuleInstance

-- | Build a host module using the builder pattern.
buildHostModule :: Text -> (ModuleBuilder -> IO ()) -> IO ModuleInstance
buildHostModule name act = do
  modInst <- createHostModule name
  act (ModuleBuilder modInst)
  pure modInst

-- | Add a function in a 'ModuleBuilder'.
builderAddFunction :: ModuleBuilder -> Text -> FunctionInstance -> IO ()
builderAddFunction (ModuleBuilder m) = addFunction m

-- | Add a typed Haskell host function to a host module builder, automatically
-- inferring its WebAssembly signature and handling argument/result conversions.
builderAddHostFunc :: (ToHostFunc f) => ModuleBuilder -> Text -> f -> IO ()
builderAddHostFunc (ModuleBuilder m) name fn = do
  fnInst <- createHostFunction fn
  addFunction m name fnInst

-- | Add a table in a 'ModuleBuilder'.
builderAddTable :: ModuleBuilder -> Text -> TableInstance -> IO ()
builderAddTable (ModuleBuilder m) = addTable m

-- | Add a memory in a 'ModuleBuilder'.
builderAddMemory :: ModuleBuilder -> Text -> MemoryInstance -> IO ()
builderAddMemory (ModuleBuilder m) = addMemory m

-- | Add a global in a 'ModuleBuilder'.
builderAddGlobal :: ModuleBuilder -> Text -> GlobalInstance -> IO ()
builderAddGlobal (ModuleBuilder m) = addGlobal m

-- ---------------------------------------------------------------------------
-- Unsafe / internal pointer helpers
-- ---------------------------------------------------------------------------

-- | Extract the raw pointer of a 'ModuleInstance'.
unsafeModulePtr :: ModuleInstance -> IO (Ptr ModuleInstanceTag)
unsafeModulePtr (ModuleInstance o) = withOwned o pure

-- | Create a borrowed 'ModuleInstance' from a raw pointer (does not finalize).
borrowModule :: Ptr ModuleInstanceTag -> IO ModuleInstance
borrowModule p = ModuleInstance <$> mkOwned (\_ -> pure ()) p

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

withCStrings :: [Text] -> (Word32 -> Ptr CString -> IO a) -> IO a
withCStrings texts action = go texts []
  where
    go [] acc =
      withArray (reverse acc) $ \ptr ->
        action (fromIntegral (length texts)) ptr
    go (t:ts) acc =
      BS.useAsCString (TE.encodeUtf8 t) $ \cstr ->
        go ts (cstr : acc)

peekStringList :: Ptr CString_ -> Word32 -> IO [Text]
peekStringList arr len =
  forM [0 .. fromIntegral len - 1] $ \i -> do
    let ptr = arr `plusPtr` (i * stringSize)
    peekWasmString ptr

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr fp p = mkDeleter fp p

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
