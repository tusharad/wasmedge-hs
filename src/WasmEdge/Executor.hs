{- |
Module      : WasmEdge.Executor
Description : WasmEdge executor context for low-level module lifecycle and invocation
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : stable

The 'Executor' context executes WebAssembly instructions, manages module
instantiation, and invokes exported functions. It works together with 'Store'.

For the simplest usage, consider using the high-level 'WasmEdge.VM.VM' API instead.
-}
module WasmEdge.Executor
  ( -- * Executor context
    Executor
  , createExecutor
  , deleteExecutor
  , withExecutor

    -- * AST module context
  , ASTModule (..)
  , loadASTFromFile
  , loadASTFromBytes
  , deleteASTModule
  , withASTModule
  , validateAST

    -- * Instantiation and registration
  , instantiateModule
  , registerModule
  , registerImportModule
  , registerImportModuleWithAlias

    -- * Function invocation
  , invokeFunction
  , asyncInvokeFunction

    -- * Internal / borrowed pointers
  , unsafeExecutorPtr
  , borrowExecutor
  , unsafeASTModulePtr
  , borrowASTModule
  ) where

import Control.Exception (bracket, throwIO)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Word (Word32)
import Foreign.C.String (withCString)
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr (FunPtr, Ptr, castPtr, nullPtr)
import Foreign.Storable (peek)

import WasmEdge.Async (Async (..), mkAsync)
import WasmEdge.Configure (Configure, unsafeConfigurePtr)
import WasmEdge.Error
import WasmEdge.Function
  ( FunctionInstance
  , getFunctionType
  , getFunctionTypeReturns
  , unsafeFunctionPtr
  )
import WasmEdge.Internal.FFI.AST (c_ASTModuleDelete)
import WasmEdge.Internal.FFI.Execution
import WasmEdge.Internal.Ownership (OwnedCtx, finalizeOwned, mkOwned, withOwned)
import WasmEdge.Internal.Storable (allocaCResult)
import WasmEdge.Internal.Types (ASTModuleTag, ExecutorTag)
import WasmEdge.Internal.Utils (checkResult, withWasmBytes, withWasmString)
import WasmEdge.Module (ModuleInstance (..), ownModule, unsafeModulePtr)
import WasmEdge.Statistics (Statistics, unsafeStatisticsPtr)
import WasmEdge.Store (Store, unsafeStorePtr)
import WasmEdge.Types
import WasmEdge.Value (peekValArray, withCValueArray, withValArray)

-- ---------------------------------------------------------------------------
-- Executor context
-- ---------------------------------------------------------------------------

-- | Low-level execution context.
newtype Executor = Executor (OwnedCtx ExecutorTag)

-- | Create an 'Executor' with optional configuration and statistics contexts.
createExecutor :: Maybe Configure -> Maybe Statistics -> IO Executor
createExecutor mCfg mStat = do
  cfgPtr <- maybe (pure nullPtr) unsafeConfigurePtr mCfg
  statPtr <- maybe (pure nullPtr) unsafeStatisticsPtr mStat
  p <- c_ExecutorCreate cfgPtr statPtr
  if p == nullPtr
    then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_ExecutorCreate returned NULL"
    else Executor <$> mkOwned (appFunPtr c_ExecutorDelete) p

-- | Delete an 'Executor'.
deleteExecutor :: Executor -> IO ()
deleteExecutor (Executor o) = finalizeOwned o

-- | Scoped 'Executor'.
withExecutor :: Maybe Configure -> Maybe Statistics -> (Executor -> IO a) -> IO a
withExecutor mCfg mStat = bracket (createExecutor mCfg mStat) deleteExecutor

-- ---------------------------------------------------------------------------
-- ASTModule context
-- ---------------------------------------------------------------------------

-- | Parsed WebAssembly Abstract Syntax Tree module.
newtype ASTModule = ASTModule (OwnedCtx ASTModuleTag)

-- | Load and parse an 'ASTModule' from a WASM file on disk.
loadASTFromFile :: FilePath -> IO (WasmResult ASTModule)
loadASTFromFile path = do
  loader <- c_LoaderCreate nullPtr
  if loader == nullPtr
    then pure $ Left $ WasmEdgeError ErrCategory_WASM 0 "Failed to create Loader"
    else alloca $ \astOut ->
      withCString path $ \cPath ->
        allocaCResult $ \resPtr -> do
          c_LoaderParseFromFile resPtr loader astOut cPath
          res <- checkResult resPtr
          appFunPtr c_LoaderDelete loader
          case res of
            Left err -> pure (Left err)
            Right () -> do
              astPtr <- peek astOut
              if astPtr == nullPtr
                then pure $ Left $ WasmEdgeError ErrCategory_WASM 0 "Parsed ASTModule is NULL"
                else Right . ASTModule <$> mkOwned (appFunPtr c_ASTModuleDelete) astPtr

-- | Load and parse an 'ASTModule' from an in-memory WASM binary.
loadASTFromBytes :: ByteString -> IO (WasmResult ASTModule)
loadASTFromBytes bs = do
  loader <- c_LoaderCreate nullPtr
  if loader == nullPtr
    then pure $ Left $ WasmEdgeError ErrCategory_WASM 0 "Failed to create Loader"
    else alloca $ \astOut ->
      withWasmBytes bs $ \bytesPtr ->
        allocaCResult $ \resPtr -> do
          -- Pass bytes pointer to loader
          c_LoaderParseFromBytes resPtr loader astOut bytesPtr
          res <- checkResult resPtr
          appFunPtr c_LoaderDelete loader
          case res of
            Left err -> pure (Left err)
            Right () -> do
              astPtr <- peek astOut
              if astPtr == nullPtr
                then pure $ Left $ WasmEdgeError ErrCategory_WASM 0 "Parsed ASTModule is NULL"
                else Right . ASTModule <$> mkOwned (appFunPtr c_ASTModuleDelete) astPtr

-- | Delete an 'ASTModule'.
deleteASTModule :: ASTModule -> IO ()
deleteASTModule (ASTModule o) = finalizeOwned o

-- | Scoped 'ASTModule'.
withASTModule :: ASTModule -> (ASTModule -> IO a) -> IO a
withASTModule ast = bracket (pure ast) deleteASTModule

-- | Validate an 'ASTModule'.
validateAST :: ASTModule -> IO (WasmResult ())
validateAST (ASTModule o) =
  withOwned o $ \astPtr -> do
    val <- c_ValidatorCreate nullPtr
    if val == nullPtr
      then pure $ Left $ WasmEdgeError ErrCategory_WASM 0 "Failed to create Validator"
      else allocaCResult $ \resPtr -> do
        c_ValidatorValidate resPtr val astPtr
        res <- checkResult resPtr
        appFunPtr c_ValidatorDelete val
        pure res

-- ---------------------------------------------------------------------------
-- Instantiation and registration
-- ---------------------------------------------------------------------------

-- | Instantiate an 'ASTModule' into a 'Store', returning the new 'ModuleInstance'.
instantiateModule :: Executor -> Store -> ASTModule -> IO (WasmResult ModuleInstance)
instantiateModule (Executor execOwned) store (ASTModule astOwned) =
  withOwned execOwned $ \execPtr ->
    withOwned astOwned $ \astPtr -> do
      storePtr <- unsafeStorePtr store
      alloca $ \outMod ->
        allocaCResult $ \resPtr -> do
          c_ExecutorInstantiate resPtr execPtr outMod storePtr astPtr
          res <- checkResult resPtr
          case res of
            Left err -> pure (Left err)
            Right () -> do
              p <- peek outMod
              if p == nullPtr
                then pure $ Left $ WasmEdgeError ErrCategory_WASM 0 "Instantiate returned NULL module"
                else Right <$> ownModule p

-- | Instantiate and register an 'ASTModule' under an export name into a 'Store'.
registerModule :: Executor -> Store -> ASTModule -> Text -> IO (WasmResult ModuleInstance)
registerModule (Executor execOwned) store (ASTModule astOwned) name =
  withOwned execOwned $ \execPtr ->
    withOwned astOwned $ \astPtr ->
      withWasmString name $ \namePtr -> do
        storePtr <- unsafeStorePtr store
        alloca $ \outMod ->
          allocaCResult $ \resPtr -> do
            c_ExecutorRegister resPtr execPtr outMod storePtr astPtr namePtr
            res <- checkResult resPtr
            case res of
              Left err -> pure (Left err)
              Right () -> do
                p <- peek outMod
                if p == nullPtr
                  then pure $ Left $ WasmEdgeError ErrCategory_WASM 0 "Register returned NULL module"
                  else Right <$> ownModule p

-- | Register a pre-created 'ModuleInstance' (e.g. host module or WASI) into a 'Store'.
registerImportModule :: Executor -> Store -> ModuleInstance -> IO (WasmResult ())
registerImportModule (Executor execOwned) store modInst =
  withOwned execOwned $ \execPtr -> do
    storePtr <- unsafeStorePtr store
    modPtr <- unsafeModulePtr modInst
    allocaCResult $ \resPtr -> do
      c_ExecutorRegisterImport resPtr execPtr storePtr modPtr
      checkResult resPtr

-- | Register a pre-created 'ModuleInstance' under a custom alias name into a 'Store'.
registerImportModuleWithAlias :: Executor -> Store -> ModuleInstance -> Text -> IO (WasmResult ())
registerImportModuleWithAlias (Executor execOwned) store modInst alias =
  withOwned execOwned $ \execPtr -> do
    storePtr <- unsafeStorePtr store
    modPtr <- unsafeModulePtr modInst
    withWasmString alias $ \aliasPtr ->
      allocaCResult $ \resPtr -> do
        c_ExecutorRegisterImportWithAlias resPtr execPtr storePtr modPtr aliasPtr
        checkResult resPtr

-- ---------------------------------------------------------------------------
-- Invocation
-- ---------------------------------------------------------------------------

-- | Synchronously invoke a 'FunctionInstance' with arguments, returning results.
invokeFunction :: Executor -> FunctionInstance -> [WasmVal] -> IO (WasmResult [WasmVal])
invokeFunction (Executor execOwned) fn params =
  withOwned execOwned $ \execPtr -> do
    fnPtr <- unsafeFunctionPtr fn
    ft <- getFunctionType fn
    retTys <- getFunctionTypeReturns ft
    let rLen = fromIntegral (length retTys) :: Word32
    withValArray params $ \paramsPtr pLen ->
      withCValueArray (fromIntegral rLen) $ \retsPtr ->
        allocaCResult $ \resPtr -> do
          c_ExecutorInvoke resPtr execPtr fnPtr (castPtr paramsPtr) pLen (castPtr retsPtr) rLen
          res <- checkResult resPtr
          case res of
            Left err -> pure (Left err)
            Right () -> Right <$> peekValArray (castPtr retsPtr) rLen

-- | Asynchronously invoke a 'FunctionInstance', returning an 'Async' handle.
asyncInvokeFunction :: Executor -> FunctionInstance -> [WasmVal] -> IO Async
asyncInvokeFunction (Executor execOwned) fn params =
  withOwned execOwned $ \execPtr -> do
    fnPtr <- unsafeFunctionPtr fn
    withValArray params $ \paramsPtr pLen -> do
      asyncPtr <- c_ExecutorAsyncInvoke execPtr fnPtr (castPtr paramsPtr) pLen
      if asyncPtr == nullPtr
        then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_ExecutorAsyncInvoke returned NULL"
        else mkAsync asyncPtr

-- ---------------------------------------------------------------------------
-- Unsafe / internal pointer helpers
-- ---------------------------------------------------------------------------

-- | Extract the raw pointer of an 'Executor'.
unsafeExecutorPtr :: Executor -> IO (Ptr ExecutorTag)
unsafeExecutorPtr (Executor o) = withOwned o pure

-- | Create a borrowed 'Executor' from a raw pointer (does not finalize).
borrowExecutor :: Ptr ExecutorTag -> IO Executor
borrowExecutor p = Executor <$> mkOwned (\_ -> pure ()) p

-- | Extract the raw pointer of an 'ASTModule'.
unsafeASTModulePtr :: ASTModule -> IO (Ptr ASTModuleTag)
unsafeASTModulePtr (ASTModule o) = withOwned o pure

-- | Create a borrowed 'ASTModule' from a raw pointer (does not finalize).
borrowASTModule :: Ptr ASTModuleTag -> IO ASTModule
borrowASTModule p = ASTModule <$> mkOwned (\_ -> pure ()) p

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr = mkDeleter

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
