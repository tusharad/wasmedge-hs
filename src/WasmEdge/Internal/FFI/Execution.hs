-- |
-- Module      : WasmEdge.Internal.FFI.Execution
-- Description : Raw FFI for loader, validator, executor, store, and async contexts
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : internal
{-# LANGUAGE ForeignFunctionInterface #-}
module WasmEdge.Internal.FFI.Execution
  ( -- * Loader
    c_LoaderCreate
  , c_LoaderDelete
  , c_LoaderParseFromFile
  , c_LoaderParseFromBytes
  , c_LoaderSerializeASTModule
    -- * Validator
  , c_ValidatorCreate
  , c_ValidatorDelete
  , c_ValidatorValidate
    -- * Executor
  , c_ExecutorCreate
  , c_ExecutorDelete
  , c_ExecutorInstantiate
  , c_ExecutorRegister
  , c_ExecutorRegisterImport
  , c_ExecutorInvoke
  , c_ExecutorAsyncInvoke
  , c_ExecutorExperimentalRegisterPreHostFunction
  , c_ExecutorExperimentalRegisterPostHostFunction
    -- * Store
  , c_StoreCreate
  , c_StoreDelete
  , c_StoreFindModule
  , c_StoreListModuleLength
  , c_StoreListModule
    -- * Async
  , c_AsyncWait
  , c_AsyncWaitFor
  , c_AsyncCancel
  , c_AsyncGetReturnsLength
  , c_AsyncGet
  , c_AsyncDelete
  ) where

import Foreign.C
import Foreign.Ptr
import Data.Word (Word32, Word64)

import WasmEdge.Internal.Types
import WasmEdge.Internal.Storable (CResult_, CBytes_, CString_)

-- ---------------------------------------------------------------------------
-- Loader
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "WasmEdge_LoaderCreate"
  c_LoaderCreate :: Ptr ConfigureTag -> IO (Ptr LoaderTag)

foreign import ccall unsafe "&WasmEdge_LoaderDelete"
  c_LoaderDelete :: FunPtr (Ptr LoaderTag -> IO ())

foreign import ccall unsafe "hs_WasmEdge_LoaderParseFromFile"
  c_LoaderParseFromFile :: Ptr CResult_
                         -> Ptr LoaderTag
                         -> Ptr (Ptr ASTModuleTag)
                         -> CString
                         -> IO ()

foreign import ccall unsafe "hs_WasmEdge_LoaderParseFromBytes"
  c_LoaderParseFromBytes :: Ptr CResult_
                          -> Ptr LoaderTag
                          -> Ptr (Ptr ASTModuleTag)
                          -> Ptr CBytes_
                          -> IO ()

foreign import ccall unsafe "hs_WasmEdge_LoaderSerializeASTModule"
  c_LoaderSerializeASTModule :: Ptr CResult_
                               -> Ptr LoaderTag
                               -> Ptr ASTModuleTag
                               -> Ptr CBytes_
                               -> IO ()

-- ---------------------------------------------------------------------------
-- Validator
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "WasmEdge_ValidatorCreate"
  c_ValidatorCreate :: Ptr ConfigureTag -> IO (Ptr ValidatorTag)

foreign import ccall unsafe "&WasmEdge_ValidatorDelete"
  c_ValidatorDelete :: FunPtr (Ptr ValidatorTag -> IO ())

foreign import ccall safe "hs_WasmEdge_ValidatorValidate"
  c_ValidatorValidate :: Ptr CResult_
                       -> Ptr ValidatorTag
                       -> Ptr ASTModuleTag
                       -> IO ()

-- ---------------------------------------------------------------------------
-- Executor
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "WasmEdge_ExecutorCreate"
  c_ExecutorCreate :: Ptr ConfigureTag -> Ptr StatisticsTag -> IO (Ptr ExecutorTag)

foreign import ccall unsafe "&WasmEdge_ExecutorDelete"
  c_ExecutorDelete :: FunPtr (Ptr ExecutorTag -> IO ())

foreign import ccall safe "hs_WasmEdge_ExecutorInstantiate"
  c_ExecutorInstantiate :: Ptr CResult_
                          -> Ptr ExecutorTag
                          -> Ptr (Ptr ModuleInstanceTag)
                          -> Ptr StoreTag
                          -> Ptr ASTModuleTag
                          -> IO ()

foreign import ccall safe "hs_WasmEdge_ExecutorRegister"
  c_ExecutorRegister :: Ptr CResult_
                       -> Ptr ExecutorTag
                       -> Ptr (Ptr ModuleInstanceTag)
                       -> Ptr StoreTag
                       -> Ptr ASTModuleTag
                       -> Ptr CString_
                       -> IO ()

foreign import ccall safe "hs_WasmEdge_ExecutorRegisterImport"
  c_ExecutorRegisterImport :: Ptr CResult_
                             -> Ptr ExecutorTag
                             -> Ptr StoreTag
                             -> Ptr ModuleInstanceTag
                             -> IO ()

foreign import ccall safe "hs_WasmEdge_ExecutorInvoke"
  c_ExecutorInvoke :: Ptr CResult_
                    -> Ptr ExecutorTag
                    -> Ptr FunctionInstanceTag
                    -> Ptr ()   -- const WasmEdge_Value* params
                    -> Word32
                    -> Ptr ()   -- WasmEdge_Value* returns
                    -> Word32
                    -> IO ()

foreign import ccall safe "WasmEdge_ExecutorAsyncInvoke"
  c_ExecutorAsyncInvoke :: Ptr ExecutorTag
                          -> Ptr FunctionInstanceTag
                          -> Ptr ()   -- const WasmEdge_Value* params
                          -> Word32
                          -> IO (Ptr AsyncTag)

-- Experimental hooks (safe: these store callbacks that call back into Haskell)
foreign import ccall safe "WasmEdge_ExecutorExperimentalRegisterPreHostFunction"
  c_ExecutorExperimentalRegisterPreHostFunction
    :: Ptr ExecutorTag -> Ptr () -> FunPtr (Ptr () -> IO ()) -> IO ()

foreign import ccall safe "WasmEdge_ExecutorExperimentalRegisterPostHostFunction"
  c_ExecutorExperimentalRegisterPostHostFunction
    :: Ptr ExecutorTag -> Ptr () -> FunPtr (Ptr () -> IO ()) -> IO ()

-- ---------------------------------------------------------------------------
-- Store
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "WasmEdge_StoreCreate"
  c_StoreCreate :: IO (Ptr StoreTag)

foreign import ccall unsafe "&WasmEdge_StoreDelete"
  c_StoreDelete :: FunPtr (Ptr StoreTag -> IO ())

foreign import ccall unsafe "WasmEdge_StoreFindModule"
  c_StoreFindModule :: Ptr StoreTag -> Ptr CString_ -> IO (Ptr ModuleInstanceTag)

foreign import ccall unsafe "WasmEdge_StoreListModuleLength"
  c_StoreListModuleLength :: Ptr StoreTag -> IO Word32

-- | List registered module names into a pre-allocated CString_ array.
foreign import ccall unsafe "WasmEdge_StoreListModule"
  c_StoreListModule :: Ptr StoreTag -> Ptr CString_ -> Word32 -> IO Word32

-- ---------------------------------------------------------------------------
-- Async
-- ---------------------------------------------------------------------------

foreign import ccall safe "WasmEdge_AsyncWait"
  c_AsyncWait :: Ptr AsyncTag -> IO ()

-- | Wait with a timeout in milliseconds. Returns True if the result is ready.
foreign import ccall safe "WasmEdge_AsyncWaitFor"
  c_AsyncWaitFor :: Ptr AsyncTag -> Word64 -> IO CBool

foreign import ccall unsafe "WasmEdge_AsyncCancel"
  c_AsyncCancel :: Ptr AsyncTag -> IO ()

foreign import ccall unsafe "WasmEdge_AsyncGetReturnsLength"
  c_AsyncGetReturnsLength :: Ptr AsyncTag -> IO Word32

foreign import ccall safe "hs_WasmEdge_AsyncGet"
  c_AsyncGet :: Ptr CResult_
              -> Ptr AsyncTag
              -> Ptr ()   -- WasmEdge_Value* returns
              -> Word32
              -> IO ()

foreign import ccall unsafe "&WasmEdge_AsyncDelete"
  c_AsyncDelete :: FunPtr (Ptr AsyncTag -> IO ())
