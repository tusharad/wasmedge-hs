{- |
Module      : WasmEdge.VM
Description : High-level WasmEdge VM context
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : stable

The 'VM' context provides the highest-level interface for running WASM
modules. It bundles a loader, validator, executor, and store internally.

== Quick start

@
import WasmEdge.VM
import WasmEdge.Types

main :: IO ()
main = do
  result <- withVM Nothing Nothing $ \vm -> do
    runWasmFile vm "hello.wasm" "main" []
  case result of
    Left err  -> putStrLn $ "Error: " ++ show err
    Right vals -> print vals
@

== Step-by-step pipeline

For more control, use the load → validate → instantiate → execute pipeline:

@
withVM (Just cfg) Nothing $ \vm -> do
  loadWasmFile vm "module.wasm"    >>= throwOnFail
  validate vm                       >>= throwOnFail
  instantiate vm                    >>= throwOnFail
  execute vm "run" [WasmI32 42]    >>= either throwIO pure
@
-}
module WasmEdge.VM
  ( -- * VM context
    VM
  , createVM
  , deleteVM
  , withVM

    -- * Declarative VM configuration
  , VMConfig (..)
  , defaultVMConfig
  , createVMWithConfig
  , withVMConfig

    -- * One-shot execution
  , runWasmFile
  , runWasmBytes

    -- * Async one-shot execution
  , asyncRunWasmFile
  , asyncRunWasmBytes

    -- * Module registration
  , registerModuleFromFile
  , registerModuleFromBytes
  , registerModuleFromImport

    -- * Step-by-step pipeline
  , loadWasmFile
  , loadWasmBytes
  , validate
  , instantiate
  , execute
  , executeRegistered

    -- * Async step-by-step
  , asyncExecute
  , asyncExecuteRegistered

    -- * Query
  , getFunctionType
  , getFunctionTypeRegistered
  , cleanup
  , getStore
  , getStatistics
  , listRegisteredModules
  , deleteRegisteredModule
  ) where

import Control.Exception (bracket, throwIO)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Word (Word32)
import Foreign.C (withCString)
import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.Ptr

import Control.DeepSeq (NFData (..))
import Control.Monad (forM)
import WasmEdge.Error
import WasmEdge.Function (FunctionType, borrowFunctionType)
import WasmEdge.Internal.FFI.Instance (c_FunctionTypeGetReturnsLength)
import WasmEdge.Internal.FFI.VM
import WasmEdge.Internal.Ownership
import WasmEdge.Internal.Storable (CString_, allocaCResult, stringSize)
import WasmEdge.Internal.Types
import WasmEdge.Internal.Utils (checkResult, peekWasmString, withWasmBytes, withWasmString)
import WasmEdge.Module (ModuleInstance (..))
import WasmEdge.Statistics (Statistics, borrowStatistics)
import WasmEdge.Types
import WasmEdge.Value (peekValArray, withCValueArray, withValArray)

import WasmEdge.Async qualified as Async
import WasmEdge.Configure qualified as Cfg
import WasmEdge.Store qualified as St

-- ---------------------------------------------------------------------------
-- VM newtype
-- ---------------------------------------------------------------------------

-- | Opaque WasmEdge VM context.
newtype VM = VM (OwnedCtx VMTag)

instance NFData VM where
  rnf !_ = ()

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

{- | Create a VM context.

@createVM mCfg mStore@ uses the optional 'Configure' context @mCfg@ and
optional shared 'Store' context @mStore@. Pass 'Nothing' to use defaults.
-}
createVM :: Maybe Cfg.Configure -> Maybe St.Store -> IO VM
createVM mCfg mStore = do
  cfgPtr <- maybe (pure nullPtr) Cfg.unsafeConfigurePtr mCfg
  storePtr <- maybe (pure nullPtr) St.unsafeStorePtr mStore
  ptr <- c_VMCreate cfgPtr storePtr
  if ptr == nullPtr
    then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_VMCreate returned NULL"
    else VM <$> mkOwned (appFunPtr c_VMDelete) ptr

-- | Delete a VM context explicitly.
deleteVM :: VM -> IO ()
deleteVM (VM owned) = finalizeOwned owned

-- | Scoped VM context.
withVM :: Maybe Cfg.Configure -> Maybe St.Store -> (VM -> IO a) -> IO a
withVM mCfg mStore = bracket (createVM mCfg mStore) deleteVM

-- ---------------------------------------------------------------------------
-- Declarative VM Configuration (fluent / builder alternative)
-- ---------------------------------------------------------------------------

{- | Declarative configuration record for initializing a 'VM'.
Inspired by @wasmedge-sdk@'s @VmBuilder@ in Rust.
-}
data VMConfig = VMConfig
  { vmConfigure :: !(Maybe Cfg.Configure)
  , vmStore :: !(Maybe St.Store)
  }

-- | Default VM configuration with default options and fresh store.
defaultVMConfig :: VMConfig
defaultVMConfig = VMConfig Nothing Nothing

-- | Create a VM context using a 'VMConfig'.
createVMWithConfig :: VMConfig -> IO VM
createVMWithConfig cfg = createVM (vmConfigure cfg) (vmStore cfg)

-- | Scoped VM context with declarative 'VMConfig'.
withVMConfig :: VMConfig -> (VM -> IO a) -> IO a
withVMConfig cfg = bracket (createVMWithConfig cfg) deleteVM

-- ---------------------------------------------------------------------------
-- One-shot execution
-- ---------------------------------------------------------------------------

-- | Load, instantiate, and run a WASM file in one call.
runWasmFile ::
  VM ->
  -- | Path to the .wasm or .so file
  FilePath ->
  -- | Function name
  Text ->
  -- | Parameters
  [WasmVal] ->
  IO (WasmResult [WasmVal])
runWasmFile (VM owned) path funcName params =
  withOwned owned $ \vmPtr ->
    withCString path $ \cPath ->
      withWasmString funcName $ \funcStr ->
        withValArray params $ \paramsPtr paramLen ->
          allocaCResult $ \resPtr -> do
            let maxRets = 16
            withCValueArray maxRets $ \retsPtr -> do
              c_VMRunWasmFromFile
                resPtr
                vmPtr
                cPath
                funcStr
                paramsPtr
                paramLen
                (castPtr retsPtr)
                (fromIntegral maxRets)
              r <- checkResult resPtr
              case r of
                Left err -> pure (Left err)
                Right () -> do
                  retLen <- getReturnLen vmPtr funcStr
                  Right <$> peekValArray (castPtr retsPtr) (fromIntegral retLen)

-- | Load, instantiate, and run a WASM module from a 'ByteString'.
runWasmBytes ::
  VM ->
  ByteString ->
  Text ->
  [WasmVal] ->
  IO (WasmResult [WasmVal])
runWasmBytes (VM owned) wasm funcName params =
  withOwned owned $ \vmPtr ->
    withWasmBytes wasm $ \bytesPtr ->
      withWasmString funcName $ \funcStr ->
        withValArray params $ \paramsPtr paramLen ->
          allocaCResult $ \resPtr -> do
            let maxRets = 16
            withCValueArray maxRets $ \retsPtr -> do
              c_VMRunWasmFromBuffer
                resPtr
                vmPtr
                bytesPtr
                funcStr
                paramsPtr
                paramLen
                (castPtr retsPtr)
                (fromIntegral maxRets)
              r <- checkResult resPtr
              case r of
                Left err -> pure (Left err)
                Right () -> do
                  retLen <- getReturnLen vmPtr funcStr
                  Right <$> peekValArray (castPtr retsPtr) (fromIntegral retLen)

-- ---------------------------------------------------------------------------
-- Async one-shot
-- ---------------------------------------------------------------------------

-- | Async variant of 'runWasmFile'.
asyncRunWasmFile :: VM -> FilePath -> Text -> [WasmVal] -> IO Async.Async
asyncRunWasmFile (VM owned) path funcName params =
  withOwned owned $ \vmPtr ->
    withCString path $ \cPath ->
      withWasmString funcName $ \funcStr ->
        withValArray params $ \paramsPtr paramLen -> do
          aptr <- c_VMAsyncRunWasmFromFile vmPtr cPath funcStr paramsPtr paramLen
          Async.mkAsync aptr

-- | Async variant of 'runWasmBytes'.
asyncRunWasmBytes :: VM -> ByteString -> Text -> [WasmVal] -> IO Async.Async
asyncRunWasmBytes (VM owned) wasm funcName params =
  withOwned owned $ \vmPtr ->
    withWasmBytes wasm $ \bytesPtr ->
      withWasmString funcName $ \funcStr ->
        withValArray params $ \paramsPtr paramLen -> do
          aptr <- c_VMAsyncRunWasmFromBuffer vmPtr bytesPtr funcStr paramsPtr paramLen
          Async.mkAsync aptr

-- ---------------------------------------------------------------------------
-- Module registration
-- ---------------------------------------------------------------------------

-- | Register and instantiate a named module from a file.
registerModuleFromFile :: VM -> Text -> FilePath -> IO (WasmResult ())
registerModuleFromFile (VM owned) modName path =
  withOwned owned $ \vmPtr ->
    withWasmString modName $ \modStr ->
      withCString path $ \cPath ->
        allocaCResult $ \resPtr -> do
          c_VMRegisterModuleFromFile resPtr vmPtr modStr cPath
          checkResult resPtr

-- | Register and instantiate a named module from bytes.
registerModuleFromBytes :: VM -> Text -> ByteString -> IO (WasmResult ())
registerModuleFromBytes (VM owned) modName wasm =
  withOwned owned $ \vmPtr ->
    withWasmString modName $ \modStr ->
      withWasmBytes wasm $ \bytesPtr ->
        allocaCResult $ \resPtr -> do
          c_VMRegisterModuleFromBuffer resPtr vmPtr modStr bytesPtr
          checkResult resPtr

{- | Register an existing 'ModuleInstance' into the VM.
The VM takes ownership; do not delete the module yourself after this call.
-}
registerModuleFromImport :: VM -> ModuleInstance -> IO (WasmResult ())
registerModuleFromImport (VM owned) (ModuleInstance mOwned) =
  withOwned owned $ \vmPtr ->
    withOwned mOwned $ \mPtr ->
      allocaCResult $ \resPtr -> do
        c_VMRegisterModuleFromImport resPtr vmPtr mPtr
        checkResult resPtr

-- ---------------------------------------------------------------------------
-- Step-by-step pipeline
-- ---------------------------------------------------------------------------

-- | Load a WASM file into the VM (does not validate or instantiate).
loadWasmFile :: VM -> FilePath -> IO (WasmResult ())
loadWasmFile (VM owned) path =
  withOwned owned $ \vmPtr ->
    withCString path $ \cPath ->
      allocaCResult $ \resPtr -> do
        c_VMLoadWasmFromFile resPtr vmPtr cPath
        checkResult resPtr

-- | Load a WASM module from bytes.
loadWasmBytes :: VM -> ByteString -> IO (WasmResult ())
loadWasmBytes (VM owned) wasm =
  withOwned owned $ \vmPtr ->
    withWasmBytes wasm $ \bytesPtr ->
      allocaCResult $ \resPtr -> do
        c_VMLoadWasmFromBuffer resPtr vmPtr bytesPtr
        checkResult resPtr

-- | Validate the loaded WASM module.
validate :: VM -> IO (WasmResult ())
validate (VM owned) =
  withOwned owned $ \vmPtr ->
    allocaCResult $ \resPtr -> do
      c_VMValidate resPtr vmPtr
      checkResult resPtr

-- | Instantiate the loaded and validated WASM module.
instantiate :: VM -> IO (WasmResult ())
instantiate (VM owned) =
  withOwned owned $ \vmPtr ->
    allocaCResult $ \resPtr -> do
      c_VMInstantiate resPtr vmPtr
      checkResult resPtr

-- | Execute a function in the instantiated module.
execute :: VM -> Text -> [WasmVal] -> IO (WasmResult [WasmVal])
execute (VM owned) funcName params =
  withOwned owned $ \vmPtr ->
    withWasmString funcName $ \funcStr ->
      withValArray params $ \paramsPtr paramLen ->
        allocaCResult $ \resPtr -> do
          let maxRets = 16
          withCValueArray maxRets $ \retsPtr -> do
            c_VMExecute
              resPtr
              vmPtr
              funcStr
              paramsPtr
              paramLen
              (castPtr retsPtr)
              (fromIntegral maxRets)
            r <- checkResult resPtr
            case r of
              Left err -> pure (Left err)
              Right () -> do
                retLen <- getReturnLen vmPtr funcStr
                Right <$> peekValArray (castPtr retsPtr) (fromIntegral retLen)

-- | Execute a function from a named registered module.
executeRegistered :: VM -> Text -> Text -> [WasmVal] -> IO (WasmResult [WasmVal])
executeRegistered (VM owned) modName funcName params =
  withOwned owned $ \vmPtr ->
    withWasmString modName $ \modStr ->
      withWasmString funcName $ \funcStr ->
        withValArray params $ \paramsPtr paramLen ->
          allocaCResult $ \resPtr -> do
            let maxRets = 16
            withCValueArray maxRets $ \retsPtr -> do
              c_VMExecuteRegistered
                resPtr
                vmPtr
                modStr
                funcStr
                paramsPtr
                paramLen
                (castPtr retsPtr)
                (fromIntegral maxRets)
              r <- checkResult resPtr
              case r of
                Left err -> pure (Left err)
                Right () -> do
                  retLen <- getReturnLenReg vmPtr modStr funcStr
                  Right <$> peekValArray (castPtr retsPtr) (fromIntegral retLen)

-- | Async variant of 'execute'.
asyncExecute :: VM -> Text -> [WasmVal] -> IO Async.Async
asyncExecute (VM owned) funcName params =
  withOwned owned $ \vmPtr ->
    withWasmString funcName $ \funcStr ->
      withValArray params $ \paramsPtr paramLen -> do
        aptr <- c_VMAsyncExecute vmPtr funcStr paramsPtr paramLen
        Async.mkAsync aptr

-- | Async variant of 'executeRegistered'.
asyncExecuteRegistered :: VM -> Text -> Text -> [WasmVal] -> IO Async.Async
asyncExecuteRegistered (VM owned) modName funcName params =
  withOwned owned $ \vmPtr ->
    withWasmString modName $ \modStr ->
      withWasmString funcName $ \funcStr ->
        withValArray params $ \paramsPtr paramLen -> do
          aptr <- c_VMAsyncExecuteRegistered vmPtr modStr funcStr paramsPtr paramLen
          Async.mkAsync aptr

-- ---------------------------------------------------------------------------
-- Query
-- ---------------------------------------------------------------------------

-- | Get the function type of an exported function.
getFunctionType :: VM -> Text -> IO (Maybe FunctionType)
getFunctionType (VM owned) funcName =
  withOwned owned $ \vmPtr ->
    withWasmString funcName $ \funcStr -> do
      p <- c_VMGetFunctionType vmPtr funcStr
      if p == nullPtr
        then pure Nothing
        else Just <$> borrowFunctionType p

-- | Get the function type of a function in a registered module.
getFunctionTypeRegistered :: VM -> Text -> Text -> IO (Maybe FunctionType)
getFunctionTypeRegistered (VM owned) modName funcName =
  withOwned owned $ \vmPtr ->
    withWasmString modName $ \modStr ->
      withWasmString funcName $ \funcStr -> do
        p <- c_VMGetFunctionTypeRegistered vmPtr modStr funcStr
        if p == nullPtr
          then pure Nothing
          else Just <$> borrowFunctionType p

-- | Clean up the VM (unload the current module without deleting the VM).
cleanup :: VM -> IO ()
cleanup (VM owned) = withOwned owned c_VMCleanup

-- | Get the shared 'Store' from the VM (borrowed — do NOT delete it).
getStore :: VM -> IO St.Store
getStore (VM owned) =
  withOwned owned $ \vmPtr -> do
    p <- c_VMGetStoreContext vmPtr
    St.borrowStore p

-- | Get the statistics context from the VM (borrowed).
getStatistics :: VM -> IO Statistics
getStatistics (VM owned) =
  withOwned owned $ \vmPtr -> do
    p <- c_VMGetStatisticsContext vmPtr
    borrowStatistics p

-- | List all registered module names.
listRegisteredModules :: VM -> IO [Text]
listRegisteredModules (VM owned) =
  withOwned owned $ \vmPtr -> do
    n <- c_VMListRegisteredModuleLength vmPtr
    if n == 0
      then pure []
      else do
        -- Allocate name array and query
        withCStringArray (fromIntegral n) $ \namesPtr -> do
          _ <- c_VMListRegisteredModule vmPtr namesPtr n
          peekNameArray namesPtr n

-- | Delete a registered module from the VM by name (0.18+).
deleteRegisteredModule :: VM -> Text -> IO ()
deleteRegisteredModule (VM owned) modName =
  withOwned owned $ \vmPtr ->
    withWasmString modName $ \modStr ->
      c_VMDeleteRegisteredModule vmPtr modStr

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

{- | Query the return count for a function (to allocate the return buffer).
Returns 0 if the function type cannot be determined.
-}
getReturnLen :: Ptr VMTag -> Ptr CString_ -> IO Int
getReturnLen vmPtr funcStr = do
  ftPtr <- c_VMGetFunctionType vmPtr funcStr
  if ftPtr == nullPtr
    then pure 0
    else fromIntegral <$> c_FunctionTypeGetReturnsLength ftPtr

getReturnLenReg :: Ptr VMTag -> Ptr CString_ -> Ptr CString_ -> IO Int
getReturnLenReg vmPtr modStr funcStr = do
  ftPtr <- c_VMGetFunctionTypeRegistered vmPtr modStr funcStr
  if ftPtr == nullPtr
    then pure 0
    else fromIntegral <$> c_FunctionTypeGetReturnsLength ftPtr

withCStringArray :: Int -> (Ptr CString_ -> IO a) -> IO a
withCStringArray n = allocaBytes (n * stringSize)

peekNameArray :: Ptr CString_ -> Word32 -> IO [Text]
peekNameArray arr n =
  forM [0 .. fromIntegral n - 1] $ \i -> do
    let ptr = arr `plusPtr` (i * stringSize)
    peekWasmString ptr

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr = mkDeleter

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
