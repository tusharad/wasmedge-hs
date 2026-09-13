{-# LANGUAGE ForeignFunctionInterface #-}

{- |
Module      : WasmEdge.Internal.FFI.Instance
Description : Raw FFI for all WasmEdge instance contexts
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : internal

Covers: FunctionType, FunctionInstance, TableType, TableInstance,
MemoryType, MemoryInstance, GlobalType, GlobalInstance, TagType (0.18+),
TagInstance (0.18+), CallingFrame, ModuleInstance.
-}
module WasmEdge.Internal.FFI.Instance
  ( -- * FunctionType
    c_FunctionTypeCreate
  , c_FunctionTypeDelete
  , c_FunctionTypeGetParametersLength
  , c_FunctionTypeGetParameters
  , c_FunctionTypeGetReturnsLength
  , c_FunctionTypeGetReturns

    -- * FunctionInstance
  , c_FunctionInstanceCreate
  , c_FunctionInstanceCreateBinding
  , c_FunctionInstanceDelete
  , c_FunctionInstanceGetFunctionType

    -- * Host function callback type
  , RawHostFuncT
  , mkHostFuncWrapper

    -- * TableType
  , c_TableTypeCreate
  , c_TableTypeDelete
  , c_TableTypeGetRefType
  , c_TableTypeGetLimit

    -- * TableInstance
  , c_TableInstanceCreate
  , c_TableInstanceDelete
  , c_TableInstanceGetTableType
  , c_TableInstanceGetData
  , c_TableInstanceSetData
  , c_TableInstanceGetSize
  , c_TableInstanceGrow

    -- * MemoryType
  , c_MemoryTypeCreate
  , c_MemoryTypeDelete
  , c_MemoryTypeGetLimit

    -- * MemoryInstance
  , c_MemoryInstanceCreate
  , c_MemoryInstanceDelete
  , c_MemoryInstanceGetMemoryType
  , c_MemoryInstanceGetData
  , c_MemoryInstanceSetData
  , c_MemoryInstanceGetPointer
  , c_MemoryInstanceGetPointerConst
  , c_MemoryInstanceGetPageSize
  , c_MemoryInstanceGrowPage

    -- * GlobalType
  , c_GlobalTypeCreate
  , c_GlobalTypeDelete
  , c_GlobalTypeGetValType
  , c_GlobalTypeGetMutability

    -- * GlobalInstance
  , c_GlobalInstanceCreate
  , c_GlobalInstanceDelete
  , c_GlobalInstanceGetGlobalType
  , c_GlobalInstanceGetValue
  , c_GlobalInstanceSetValue

    -- * CallingFrame
  , c_CallingFrameGetExecutor
  , c_CallingFrameGetModuleInstance
  , c_CallingFrameGetMemoryInstance

    -- * ModuleInstance
  , c_ModuleInstanceCreate
  , c_ModuleInstanceCreateWithData
  , c_ModuleInstanceCreateWASI
  , c_ModuleInstanceDelete
  , c_ModuleInstanceInitWASI
  , c_ModuleInstanceWASIGetExitCode
  , c_ModuleInstanceWASIGetNativeHandler
  , c_ModuleInstanceGetModuleName
  , c_ModuleInstanceFindFunction
  , c_ModuleInstanceFindTable
  , c_ModuleInstanceFindMemory
  , c_ModuleInstanceFindGlobal
  , c_ModuleInstanceListFunctionLength
  , c_ModuleInstanceListFunction
  , c_ModuleInstanceListTableLength
  , c_ModuleInstanceListTable
  , c_ModuleInstanceListMemoryLength
  , c_ModuleInstanceListMemory
  , c_ModuleInstanceListGlobalLength
  , c_ModuleInstanceListGlobal

    -- * Limit helper
  , c_LimitGetInfo

    -- * TagType (0.18+)
  , c_TagTypeGetFunctionType

    -- * TagInstance (0.18+)
  , c_TagInstanceGetTagType

    -- * ModuleInstance tag operations
  , c_ModuleInstanceFindTag
  , c_ModuleInstanceListTagLength
  , c_ModuleInstanceListTag
  , c_ModuleInstanceAddFunction
  , c_ModuleInstanceAddTable
  , c_ModuleInstanceAddMemory
  , c_ModuleInstanceAddGlobal
  ) where

import Data.Word (Word32, Word64, Word8)
import Foreign.C
import Foreign.Ptr

import WasmEdge.Internal.Storable (CResult_, CString_, CValType_, CValue_)
import WasmEdge.Internal.Types

-- ---------------------------------------------------------------------------
-- Host function callback
-- ---------------------------------------------------------------------------

{- | The raw C type of a WasmEdge host function callback:
@WasmEdge_Result callback(void* data, const WasmEdge_CallingFrameContext*,
                           const WasmEdge_Value* params, uint32_t param_len,
                           WasmEdge_Value* returns, uint32_t return_len)@

We use 'Ptr ()' for the value arrays since WasmEdge_Value is opaque at
this level; the public API converts them.

This callback is 'safe' because it calls back into Haskell.
-}
type RawHostFuncT =
  Ptr () -> -- host data
  Ptr CallingFrameTag -> -- calling frame
  Ptr () -> -- const WasmEdge_Value* params
  Word32 -> -- param_len
  Ptr () -> -- WasmEdge_Value* returns
  Word32 -> -- return_len
  Ptr CResult_ -> -- WasmEdge_Result* out
  IO ()

{- | Wrap a Haskell 'RawHostFuncT' into a C function pointer.
The returned 'FunPtr' must be freed with 'freeHaskellFunPtr' when
the function instance is deleted.
-}
foreign import ccall "wrapper"
  mkHostFuncWrapper :: RawHostFuncT -> IO (FunPtr RawHostFuncT)

-- ---------------------------------------------------------------------------
-- FunctionType
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "hs_WasmEdge_FunctionTypeCreate"
  c_FunctionTypeCreate ::
    Ptr CValType_ -> -- params
    Word32 -> -- param_len
    Ptr CValType_ -> -- returns
    Word32 -> -- return_len
    IO (Ptr FunctionTypeTag)

foreign import ccall unsafe "&WasmEdge_FunctionTypeDelete"
  c_FunctionTypeDelete :: FunPtr (Ptr FunctionTypeTag -> IO ())

foreign import ccall unsafe "WasmEdge_FunctionTypeGetParametersLength"
  c_FunctionTypeGetParametersLength :: Ptr FunctionTypeTag -> IO Word32

foreign import ccall unsafe "WasmEdge_FunctionTypeGetParameters"
  c_FunctionTypeGetParameters ::
    Ptr FunctionTypeTag ->
    Ptr CValType_ ->
    Word32 ->
    IO Word32

foreign import ccall unsafe "WasmEdge_FunctionTypeGetReturnsLength"
  c_FunctionTypeGetReturnsLength :: Ptr FunctionTypeTag -> IO Word32

foreign import ccall unsafe "WasmEdge_FunctionTypeGetReturns"
  c_FunctionTypeGetReturns ::
    Ptr FunctionTypeTag ->
    Ptr CValType_ ->
    Word32 ->
    IO Word32

-- ---------------------------------------------------------------------------
-- FunctionInstance
-- ---------------------------------------------------------------------------

-- | Create a host function instance.
foreign import ccall safe "hs_WasmEdge_FunctionInstanceCreateBinding"
  c_FunctionInstanceCreateBinding ::
    Ptr FunctionTypeTag ->
    FunPtr RawHostFuncT ->
    Ptr () -> -- host data
    Word64 -> -- cost
    IO (Ptr FunctionInstanceTag)

foreign import ccall safe "hs_WasmEdge_FunctionInstanceCreateBinding"
  c_FunctionInstanceCreate ::
    Ptr FunctionTypeTag ->
    FunPtr RawHostFuncT ->
    Ptr () ->
    Word64 ->
    IO (Ptr FunctionInstanceTag)

foreign import ccall unsafe "&WasmEdge_FunctionInstanceDelete"
  c_FunctionInstanceDelete :: FunPtr (Ptr FunctionInstanceTag -> IO ())

foreign import ccall unsafe "WasmEdge_FunctionInstanceGetFunctionType"
  c_FunctionInstanceGetFunctionType ::
    Ptr FunctionInstanceTag -> IO (Ptr FunctionTypeTag)

-- ---------------------------------------------------------------------------
-- TableType
-- ---------------------------------------------------------------------------

-- | Create a TableType.
foreign import ccall unsafe "hs_WasmEdge_TableTypeCreate"
  c_TableTypeCreate ::
    Ptr CValType_ -> -- ref type (ValType)
    CBool -> -- has max
    Word64 -> -- min
    Word64 -> -- max
    CBool -> -- shared
    CBool -> -- is64
    IO (Ptr TableTypeTag)

foreign import ccall unsafe "&WasmEdge_TableTypeDelete"
  c_TableTypeDelete :: FunPtr (Ptr TableTypeTag -> IO ())

foreign import ccall unsafe "hs_WasmEdge_TableTypeGetRefType"
  c_TableTypeGetRefType :: Ptr TableTypeTag -> Ptr CValType_ -> IO ()

{- | Get the limit of a table type. Returns (hasMax, min, max).
We call the individual getter functions.
-}
foreign import ccall unsafe "WasmEdge_TableTypeGetLimit"
  c_TableTypeGetLimit :: Ptr TableTypeTag -> IO (Ptr ()) -- WasmEdge_Limit opaque

-- ---------------------------------------------------------------------------
-- TableInstance
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "WasmEdge_TableInstanceCreate"
  c_TableInstanceCreate :: Ptr TableTypeTag -> IO (Ptr TableInstanceTag)

foreign import ccall unsafe "&WasmEdge_TableInstanceDelete"
  c_TableInstanceDelete :: FunPtr (Ptr TableInstanceTag -> IO ())

foreign import ccall unsafe "WasmEdge_TableInstanceGetTableType"
  c_TableInstanceGetTableType :: Ptr TableInstanceTag -> IO (Ptr TableTypeTag)

foreign import ccall unsafe "hs_WasmEdge_TableInstanceGetData"
  c_TableInstanceGetData ::
    Ptr CResult_ ->
    Ptr TableInstanceTag ->
    Ptr CValue_ ->
    Word32 ->
    IO ()

foreign import ccall unsafe "hs_WasmEdge_TableInstanceSetData"
  c_TableInstanceSetData ::
    Ptr CResult_ ->
    Ptr TableInstanceTag ->
    Ptr CValue_ ->
    Word32 ->
    IO ()

foreign import ccall unsafe "WasmEdge_TableInstanceGetSize"
  c_TableInstanceGetSize :: Ptr TableInstanceTag -> IO Word32

foreign import ccall unsafe "hs_WasmEdge_TableInstanceGrow"
  c_TableInstanceGrow :: Ptr CResult_ -> Ptr TableInstanceTag -> Word32 -> IO ()

-- ---------------------------------------------------------------------------
-- MemoryType
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "hs_WasmEdge_MemoryTypeCreate"
  c_MemoryTypeCreate ::
    CBool -> -- has max
    Word64 -> -- min pages
    Word64 -> -- max pages
    CBool -> -- shared
    CBool -> -- is64
    IO (Ptr MemoryTypeTag)

foreign import ccall unsafe "&WasmEdge_MemoryTypeDelete"
  c_MemoryTypeDelete :: FunPtr (Ptr MemoryTypeTag -> IO ())

-- | Inspect limit info via our C helper
foreign import ccall unsafe "hs_WasmEdge_LimitGetInfo"
  c_LimitGetInfo ::
    Ptr () ->
    Ptr CBool ->
    Ptr Word64 ->
    Ptr Word64 ->
    Ptr CBool ->
    Ptr CBool ->
    IO ()

-- Returns an opaque WasmEdge_Limit; inspect via individual getters
foreign import ccall unsafe "WasmEdge_MemoryTypeGetLimit"
  c_MemoryTypeGetLimit :: Ptr MemoryTypeTag -> IO (Ptr ())

-- ---------------------------------------------------------------------------
-- MemoryInstance
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "WasmEdge_MemoryInstanceCreate"
  c_MemoryInstanceCreate :: Ptr MemoryTypeTag -> IO (Ptr MemoryInstanceTag)

foreign import ccall unsafe "&WasmEdge_MemoryInstanceDelete"
  c_MemoryInstanceDelete :: FunPtr (Ptr MemoryInstanceTag -> IO ())

foreign import ccall unsafe "WasmEdge_MemoryInstanceGetMemoryType"
  c_MemoryInstanceGetMemoryType :: Ptr MemoryInstanceTag -> IO (Ptr MemoryTypeTag)

foreign import ccall unsafe "hs_WasmEdge_MemoryInstanceGetData"
  c_MemoryInstanceGetData ::
    Ptr CResult_ ->
    Ptr MemoryInstanceTag ->
    Ptr Word32 -> -- uint8_t* data
    Word32 -> -- offset
    Word32 -> -- length
    IO ()

foreign import ccall unsafe "hs_WasmEdge_MemoryInstanceSetData"
  c_MemoryInstanceSetData ::
    Ptr CResult_ ->
    Ptr MemoryInstanceTag ->
    Ptr Word32 -> -- const uint8_t* data
    Word32 -> -- offset
    Word32 -> -- length
    IO ()

foreign import ccall unsafe "WasmEdge_MemoryInstanceGetPointer"
  c_MemoryInstanceGetPointer ::
    Ptr MemoryInstanceTag ->
    Word32 -> -- offset
    Word32 -> -- length
    IO (Ptr Word8) -- uint8_t*

foreign import ccall unsafe "WasmEdge_MemoryInstanceGetPointerConst"
  c_MemoryInstanceGetPointerConst ::
    Ptr MemoryInstanceTag ->
    Word32 ->
    Word32 ->
    IO (Ptr Word8)

foreign import ccall unsafe "WasmEdge_MemoryInstanceGetPageSize"
  c_MemoryInstanceGetPageSize :: Ptr MemoryInstanceTag -> IO Word32

foreign import ccall unsafe "hs_WasmEdge_MemoryInstanceGrowPage"
  c_MemoryInstanceGrowPage :: Ptr CResult_ -> Ptr MemoryInstanceTag -> Word32 -> IO ()

-- ---------------------------------------------------------------------------
-- GlobalType
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "hs_WasmEdge_GlobalTypeCreate"
  c_GlobalTypeCreate ::
    Ptr CValType_ -> -- val type
    Word32 -> -- mutability (0=Const, 1=Var)
    IO (Ptr GlobalTypeTag)

foreign import ccall unsafe "&WasmEdge_GlobalTypeDelete"
  c_GlobalTypeDelete :: FunPtr (Ptr GlobalTypeTag -> IO ())

foreign import ccall unsafe "hs_WasmEdge_GlobalTypeGetValType"
  c_GlobalTypeGetValType :: Ptr GlobalTypeTag -> Ptr CValType_ -> IO ()

foreign import ccall unsafe "WasmEdge_GlobalTypeGetMutability"
  c_GlobalTypeGetMutability :: Ptr GlobalTypeTag -> IO Word32

-- ---------------------------------------------------------------------------
-- GlobalInstance
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "hs_WasmEdge_GlobalInstanceCreate"
  c_GlobalInstanceCreate :: Ptr GlobalTypeTag -> Ptr CValue_ -> IO (Ptr GlobalInstanceTag)

foreign import ccall unsafe "&WasmEdge_GlobalInstanceDelete"
  c_GlobalInstanceDelete :: FunPtr (Ptr GlobalInstanceTag -> IO ())

foreign import ccall unsafe "WasmEdge_GlobalInstanceGetGlobalType"
  c_GlobalInstanceGetGlobalType :: Ptr GlobalInstanceTag -> IO (Ptr GlobalTypeTag)

foreign import ccall unsafe "hs_WasmEdge_GlobalInstanceGetValue"
  c_GlobalInstanceGetValue :: Ptr CValue_ -> Ptr GlobalInstanceTag -> IO ()

foreign import ccall unsafe "hs_WasmEdge_GlobalInstanceSetValue"
  c_GlobalInstanceSetValue :: Ptr CResult_ -> Ptr GlobalInstanceTag -> Ptr CValue_ -> IO ()

-- ---------------------------------------------------------------------------
-- CallingFrame
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "WasmEdge_CallingFrameGetExecutor"
  c_CallingFrameGetExecutor :: Ptr CallingFrameTag -> IO (Ptr ExecutorTag)

foreign import ccall unsafe "WasmEdge_CallingFrameGetModuleInstance"
  c_CallingFrameGetModuleInstance :: Ptr CallingFrameTag -> IO (Ptr ModuleInstanceTag)

foreign import ccall unsafe "WasmEdge_CallingFrameGetMemoryInstance"
  c_CallingFrameGetMemoryInstance :: Ptr CallingFrameTag -> Word32 -> IO (Ptr MemoryInstanceTag)

-- ---------------------------------------------------------------------------
-- ModuleInstance
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceCreate"
  c_ModuleInstanceCreate :: Ptr CString_ -> IO (Ptr ModuleInstanceTag)

-- | Create with host data and a finalizer for the data.
foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceCreateWithData"
  c_ModuleInstanceCreateWithData ::
    Ptr CString_ ->
    Ptr () -> -- host data
    FunPtr (Ptr () -> IO ()) -> -- finalizer
    IO (Ptr ModuleInstanceTag)

foreign import ccall unsafe "WasmEdge_ModuleInstanceCreateWASI"
  c_ModuleInstanceCreateWASI ::
    Ptr CString -> -- argv[]
    Word32 -> -- argc
    Ptr CString -> -- envs[]
    Word32 -> -- envLen
    Ptr CString -> -- preopens[]
    Word32 -> -- preopenLen
    IO (Ptr ModuleInstanceTag)

foreign import ccall unsafe "&WasmEdge_ModuleInstanceDelete"
  c_ModuleInstanceDelete :: FunPtr (Ptr ModuleInstanceTag -> IO ())

foreign import ccall unsafe "WasmEdge_ModuleInstanceInitWASI"
  c_ModuleInstanceInitWASI ::
    Ptr ModuleInstanceTag ->
    Ptr CString -> -- argv[]
    Word32 ->
    Ptr CString -> -- envs[]
    Word32 ->
    Ptr CString -> -- preopens[]
    Word32 ->
    IO ()

foreign import ccall unsafe "WasmEdge_ModuleInstanceWASIGetExitCode"
  c_ModuleInstanceWASIGetExitCode :: Ptr ModuleInstanceTag -> IO Word32

foreign import ccall unsafe "WasmEdge_ModuleInstanceWASIGetNativeHandler"
  c_ModuleInstanceWASIGetNativeHandler ::
    Ptr ModuleInstanceTag ->
    Word32 -> -- fd
    Ptr Word64 -> -- out native handle
    IO CBool

foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceGetModuleName"
  c_ModuleInstanceGetModuleName :: Ptr CString_ -> Ptr ModuleInstanceTag -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceFindFunction"
  c_ModuleInstanceFindFunction ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    IO (Ptr FunctionInstanceTag)

foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceFindTable"
  c_ModuleInstanceFindTable ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    IO (Ptr TableInstanceTag)

foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceFindMemory"
  c_ModuleInstanceFindMemory ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    IO (Ptr MemoryInstanceTag)

foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceFindGlobal"
  c_ModuleInstanceFindGlobal ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    IO (Ptr GlobalInstanceTag)

foreign import ccall unsafe "WasmEdge_ModuleInstanceListFunctionLength"
  c_ModuleInstanceListFunctionLength :: Ptr ModuleInstanceTag -> IO Word32

foreign import ccall unsafe "WasmEdge_ModuleInstanceListFunction"
  c_ModuleInstanceListFunction ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    Word32 ->
    IO Word32

foreign import ccall unsafe "WasmEdge_ModuleInstanceListTableLength"
  c_ModuleInstanceListTableLength :: Ptr ModuleInstanceTag -> IO Word32

foreign import ccall unsafe "WasmEdge_ModuleInstanceListTable"
  c_ModuleInstanceListTable ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    Word32 ->
    IO Word32

foreign import ccall unsafe "WasmEdge_ModuleInstanceListMemoryLength"
  c_ModuleInstanceListMemoryLength :: Ptr ModuleInstanceTag -> IO Word32

foreign import ccall unsafe "WasmEdge_ModuleInstanceListMemory"
  c_ModuleInstanceListMemory ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    Word32 ->
    IO Word32

foreign import ccall unsafe "WasmEdge_ModuleInstanceListGlobalLength"
  c_ModuleInstanceListGlobalLength :: Ptr ModuleInstanceTag -> IO Word32

foreign import ccall unsafe "WasmEdge_ModuleInstanceListGlobal"
  c_ModuleInstanceListGlobal ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    Word32 ->
    IO Word32

-- | Add a FunctionInstance to a ModuleInstance (moves ownership into module).
foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceAddFunction"
  c_ModuleInstanceAddFunction ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    Ptr FunctionInstanceTag ->
    IO ()

foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceAddTable"
  c_ModuleInstanceAddTable ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    Ptr TableInstanceTag ->
    IO ()

foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceAddMemory"
  c_ModuleInstanceAddMemory ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    Ptr MemoryInstanceTag ->
    IO ()

foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceAddGlobal"
  c_ModuleInstanceAddGlobal ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    Ptr GlobalInstanceTag ->
    IO ()

-- ---------------------------------------------------------------------------
-- TagType & TagInstance (0.18+)
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "WasmEdge_TagInstanceGetTagType"
  c_TagInstanceGetTagType :: Ptr TagInstanceTag -> IO (Ptr TagTypeTag)

foreign import ccall unsafe "WasmEdge_TagTypeGetFunctionType"
  c_TagTypeGetFunctionType :: Ptr TagTypeTag -> IO (Ptr FunctionTypeTag)

foreign import ccall unsafe "hs_WasmEdge_ModuleInstanceFindTag"
  c_ModuleInstanceFindTag ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    IO (Ptr TagInstanceTag)

foreign import ccall unsafe "WasmEdge_ModuleInstanceListTagLength"
  c_ModuleInstanceListTagLength :: Ptr ModuleInstanceTag -> IO Word32

foreign import ccall unsafe "WasmEdge_ModuleInstanceListTag"
  c_ModuleInstanceListTag ::
    Ptr ModuleInstanceTag ->
    Ptr CString_ ->
    Word32 ->
    IO Word32
