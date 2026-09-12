{-# LANGUAGE ForeignFunctionInterface #-}

{- |
Module      : WasmEdge.Internal.FFI.VM
Description : Raw FFI for WasmEdge VM context
Copyright   : (c) wasmedge-hs contributors, 2026
License     : Apache-2.0
Stability   : internal
-}
module WasmEdge.Internal.FFI.VM
  ( c_VMCreate
  , c_VMDelete
  , c_VMRunWasmFromFile
  , c_VMRunWasmFromBuffer
  , c_VMRunWasmFromASTModule
  , c_VMAsyncRunWasmFromFile
  , c_VMAsyncRunWasmFromBuffer
  , c_VMAsyncRunWasmFromASTModule
  , c_VMRegisterModuleFromFile
  , c_VMRegisterModuleFromBuffer
  , c_VMRegisterModuleFromASTModule
  , c_VMRegisterModuleFromImport
  , c_VMRegisterModuleFromImportWithAlias
  , c_VMLoadWasmFromFile
  , c_VMLoadWasmFromBuffer
  , c_VMLoadWasmFromASTModule
  , c_VMValidate
  , c_VMInstantiate
  , c_VMExecute
  , c_VMExecuteRegistered
  , c_VMAsyncExecute
  , c_VMAsyncExecuteRegistered
  , c_VMGetFunctionType
  , c_VMGetFunctionTypeRegistered
  , c_VMCleanup
  , c_VMGetFunctionListLength
  , c_VMGetImportModuleContext
  , c_VMGetActiveModule
  , c_VMGetRegisteredModule
  , c_VMListRegisteredModuleLength
  , c_VMListRegisteredModule
  , c_VMGetStoreContext
  , c_VMGetLoaderContext
  , c_VMGetValidatorContext
  , c_VMGetExecutorContext
  , c_VMGetStatisticsContext
  , c_VMDeleteRegisteredModule
  ) where

import Data.Word (Word32)
import Foreign.C
import Foreign.Ptr

import WasmEdge.Internal.Storable (CBytes_, CResult_, CString_)
import WasmEdge.Internal.Types

foreign import ccall unsafe "WasmEdge_VMCreate"
  c_VMCreate :: Ptr ConfigureTag -> Ptr StoreTag -> IO (Ptr VMTag)

foreign import ccall unsafe "&WasmEdge_VMDelete"
  c_VMDelete :: FunPtr (Ptr VMTag -> IO ())

-- Run from file
foreign import ccall safe "hs_WasmEdge_VMRunWasmFromFile"
  c_VMRunWasmFromFile ::
    Ptr CResult_ ->
    Ptr VMTag ->
    CString ->
    Ptr CString_ -> -- func name
    Ptr () -> -- params
    Word32 ->
    Ptr () -> -- returns
    Word32 ->
    IO ()

-- Run from buffer
foreign import ccall safe "hs_WasmEdge_VMRunWasmFromBuffer"
  c_VMRunWasmFromBuffer ::
    Ptr CResult_ ->
    Ptr VMTag ->
    Ptr CBytes_ ->
    Ptr CString_ ->
    Ptr () ->
    Word32 ->
    Ptr () ->
    Word32 ->
    IO ()

-- Run from AST Module
foreign import ccall safe "hs_WasmEdge_VMRunWasmFromASTModule"
  c_VMRunWasmFromASTModule ::
    Ptr CResult_ ->
    Ptr VMTag ->
    Ptr ASTModuleTag ->
    Ptr CString_ ->
    Ptr () ->
    Word32 ->
    Ptr () ->
    Word32 ->
    IO ()

-- Async variants
foreign import ccall safe "hs_WasmEdge_VMAsyncRunWasmFromFile"
  c_VMAsyncRunWasmFromFile ::
    Ptr VMTag ->
    CString ->
    Ptr CString_ ->
    Ptr () ->
    Word32 ->
    IO (Ptr AsyncTag)

foreign import ccall safe "hs_WasmEdge_VMAsyncRunWasmFromBytes"
  c_VMAsyncRunWasmFromBuffer ::
    Ptr VMTag ->
    Ptr CBytes_ ->
    Ptr CString_ ->
    Ptr () ->
    Word32 ->
    IO (Ptr AsyncTag)

foreign import ccall safe "hs_WasmEdge_VMAsyncRunWasmFromASTModule"
  c_VMAsyncRunWasmFromASTModule ::
    Ptr VMTag ->
    Ptr ASTModuleTag ->
    Ptr CString_ ->
    Ptr () ->
    Word32 ->
    IO (Ptr AsyncTag)

-- Register module
foreign import ccall safe "hs_WasmEdge_VMRegisterModuleFromFile"
  c_VMRegisterModuleFromFile ::
    Ptr CResult_ ->
    Ptr VMTag ->
    Ptr CString_ ->
    CString ->
    IO ()

foreign import ccall safe "hs_WasmEdge_VMRegisterModuleFromBuffer"
  c_VMRegisterModuleFromBuffer ::
    Ptr CResult_ ->
    Ptr VMTag ->
    Ptr CString_ ->
    Ptr CBytes_ ->
    IO ()

foreign import ccall safe "hs_WasmEdge_VMRegisterModuleFromASTModule"
  c_VMRegisterModuleFromASTModule ::
    Ptr CResult_ ->
    Ptr VMTag ->
    Ptr CString_ ->
    Ptr ASTModuleTag ->
    IO ()

foreign import ccall safe "hs_WasmEdge_VMRegisterModuleFromImport"
  c_VMRegisterModuleFromImport ::
    Ptr CResult_ ->
    Ptr VMTag ->
    Ptr ModuleInstanceTag ->
    IO ()

foreign import ccall safe "hs_WasmEdge_VMRegisterModuleFromImportWithAlias"
  c_VMRegisterModuleFromImportWithAlias ::
    Ptr CResult_ ->
    Ptr VMTag ->
    Ptr CString_ ->
    Ptr ModuleInstanceTag ->
    IO ()

-- Load
foreign import ccall safe "hs_WasmEdge_VMLoadWasmFromFile"
  c_VMLoadWasmFromFile :: Ptr CResult_ -> Ptr VMTag -> CString -> IO ()

foreign import ccall safe "hs_WasmEdge_VMLoadWasmFromBuffer"
  c_VMLoadWasmFromBuffer :: Ptr CResult_ -> Ptr VMTag -> Ptr CBytes_ -> IO ()

foreign import ccall safe "hs_WasmEdge_VMLoadWasmFromASTModule"
  c_VMLoadWasmFromASTModule :: Ptr CResult_ -> Ptr VMTag -> Ptr ASTModuleTag -> IO ()

-- Validate / Instantiate / Execute
foreign import ccall safe "hs_WasmEdge_VMValidate"
  c_VMValidate :: Ptr CResult_ -> Ptr VMTag -> IO ()

foreign import ccall safe "hs_WasmEdge_VMInstantiate"
  c_VMInstantiate :: Ptr CResult_ -> Ptr VMTag -> IO ()

foreign import ccall safe "hs_WasmEdge_VMExecute"
  c_VMExecute ::
    Ptr CResult_ ->
    Ptr VMTag ->
    Ptr CString_ ->
    Ptr () ->
    Word32 ->
    Ptr () ->
    Word32 ->
    IO ()

foreign import ccall safe "hs_WasmEdge_VMExecuteRegistered"
  c_VMExecuteRegistered ::
    Ptr CResult_ ->
    Ptr VMTag ->
    Ptr CString_ -> -- module name
    Ptr CString_ -> -- func name
    Ptr () ->
    Word32 ->
    Ptr () ->
    Word32 ->
    IO ()

foreign import ccall safe "hs_WasmEdge_VMAsyncExecute"
  c_VMAsyncExecute :: Ptr VMTag -> Ptr CString_ -> Ptr () -> Word32 -> IO (Ptr AsyncTag)

foreign import ccall safe "hs_WasmEdge_VMAsyncExecuteRegistered"
  c_VMAsyncExecuteRegistered ::
    Ptr VMTag ->
    Ptr CString_ ->
    Ptr CString_ ->
    Ptr () ->
    Word32 ->
    IO (Ptr AsyncTag)

-- Query
foreign import ccall unsafe "hs_WasmEdge_VMGetFunctionType"
  c_VMGetFunctionType :: Ptr VMTag -> Ptr CString_ -> IO (Ptr FunctionTypeTag)

foreign import ccall unsafe "hs_WasmEdge_VMGetFunctionTypeRegistered"
  c_VMGetFunctionTypeRegistered ::
    Ptr VMTag ->
    Ptr CString_ ->
    Ptr CString_ ->
    IO (Ptr FunctionTypeTag)

foreign import ccall unsafe "WasmEdge_VMCleanup"
  c_VMCleanup :: Ptr VMTag -> IO ()

foreign import ccall unsafe "WasmEdge_VMGetFunctionListLength"
  c_VMGetFunctionListLength :: Ptr VMTag -> IO Word32

foreign import ccall unsafe "WasmEdge_VMGetImportModuleContext"
  c_VMGetImportModuleContext :: Ptr VMTag -> Word32 -> IO (Ptr ModuleInstanceTag)

foreign import ccall unsafe "WasmEdge_VMGetActiveModule"
  c_VMGetActiveModule :: Ptr VMTag -> IO (Ptr ModuleInstanceTag)

foreign import ccall unsafe "hs_WasmEdge_VMGetRegisteredModule"
  c_VMGetRegisteredModule :: Ptr VMTag -> Ptr CString_ -> IO (Ptr ModuleInstanceTag)

foreign import ccall unsafe "WasmEdge_VMListRegisteredModuleLength"
  c_VMListRegisteredModuleLength :: Ptr VMTag -> IO Word32

foreign import ccall unsafe "WasmEdge_VMListRegisteredModule"
  c_VMListRegisteredModule :: Ptr VMTag -> Ptr CString_ -> Word32 -> IO Word32

foreign import ccall unsafe "WasmEdge_VMGetStoreContext"
  c_VMGetStoreContext :: Ptr VMTag -> IO (Ptr StoreTag)

foreign import ccall unsafe "WasmEdge_VMGetLoaderContext"
  c_VMGetLoaderContext :: Ptr VMTag -> IO (Ptr LoaderTag)

foreign import ccall unsafe "WasmEdge_VMGetValidatorContext"
  c_VMGetValidatorContext :: Ptr VMTag -> IO (Ptr ValidatorTag)

foreign import ccall unsafe "WasmEdge_VMGetExecutorContext"
  c_VMGetExecutorContext :: Ptr VMTag -> IO (Ptr ExecutorTag)

foreign import ccall unsafe "WasmEdge_VMGetStatisticsContext"
  c_VMGetStatisticsContext :: Ptr VMTag -> IO (Ptr StatisticsTag)

-- | Delete (unregister) a registered module from the VM.
foreign import ccall unsafe "hs_WasmEdge_VMForceDeleteRegisteredModule"
  c_VMDeleteRegisteredModule :: Ptr VMTag -> Ptr CString_ -> IO ()
