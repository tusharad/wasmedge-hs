-- |
-- Module      : WasmEdge.Internal.FFI.Value
-- Description : Raw FFI for WasmEdge value types and value gen/get
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : internal
--
-- __Do not import this module in user code.__
{-# LANGUAGE ForeignFunctionInterface #-}
module WasmEdge.Internal.FFI.Value
  ( -- * ValType generators (via shims)
    c_ValTypeGenI32
  , c_ValTypeGenI64
  , c_ValTypeGenF32
  , c_ValTypeGenF64
  , c_ValTypeGenV128
  , c_ValTypeGenFuncRef
  , c_ValTypeGenExternRef
    -- * ValType predicates
  , c_ValTypeIsEqual
  , c_ValTypeIsI32
  , c_ValTypeIsI64
  , c_ValTypeIsF32
  , c_ValTypeIsF64
  , c_ValTypeIsV128
  , c_ValTypeIsFuncRef
  , c_ValTypeIsExternRef
  , c_ValTypeIsRef
  , c_ValTypeIsRefNull
    -- * Value generators (via shims)
  , c_ValueGenI32
  , c_ValueGenI64
  , c_ValueGenF32
  , c_ValueGenF64
  , c_ValueGenV128
  , c_ValueGenFuncRef
  , c_ValueGenExternRef
  , c_ValueGenNullFuncRef
  , c_ValueGenNullExternRef
    -- * Value extractors
  , c_ValueGetI32
  , c_ValueGetI64
  , c_ValueGetF32
  , c_ValueGetF64
  , c_ValueGetV128
  , c_ValueIsNullRef
  , c_ValueGetFuncRef
  , c_ValueGetExternRef
  , c_ValueGetType
    -- * Value array helpers
  , c_ValueArrayAlloc
  , c_ValueArrayFree
  , c_ValueArraySet
  , c_ValueArrayGet
  ) where

import Foreign.C
import Foreign.Ptr
import Data.Word (Word32, Word64)
import Data.Int  (Int32, Int64)

import WasmEdge.Internal.Storable (CValType_, CValue_)
import WasmEdge.Internal.Types    (FunctionInstanceTag)

-- ---------------------------------------------------------------------------
-- ValType generators
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "hs_WasmEdge_ValTypeGenI32"
  c_ValTypeGenI32 :: Ptr CValType_ -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ValTypeGenI64"
  c_ValTypeGenI64 :: Ptr CValType_ -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ValTypeGenF32"
  c_ValTypeGenF32 :: Ptr CValType_ -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ValTypeGenF64"
  c_ValTypeGenF64 :: Ptr CValType_ -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ValTypeGenV128"
  c_ValTypeGenV128 :: Ptr CValType_ -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ValTypeGenFuncRef"
  c_ValTypeGenFuncRef :: Ptr CValType_ -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ValTypeGenExternRef"
  c_ValTypeGenExternRef :: Ptr CValType_ -> IO ()

-- ---------------------------------------------------------------------------
-- ValType predicates
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "hs_WasmEdge_ValTypeIsEqual"
  c_ValTypeIsEqual :: Ptr CValType_ -> Ptr CValType_ -> IO CBool

foreign import ccall unsafe "hs_WasmEdge_ValTypeIsI32"
  c_ValTypeIsI32 :: Ptr CValType_ -> IO CBool

foreign import ccall unsafe "hs_WasmEdge_ValTypeIsI64"
  c_ValTypeIsI64 :: Ptr CValType_ -> IO CBool

foreign import ccall unsafe "hs_WasmEdge_ValTypeIsF32"
  c_ValTypeIsF32 :: Ptr CValType_ -> IO CBool

foreign import ccall unsafe "hs_WasmEdge_ValTypeIsF64"
  c_ValTypeIsF64 :: Ptr CValType_ -> IO CBool

foreign import ccall unsafe "hs_WasmEdge_ValTypeIsV128"
  c_ValTypeIsV128 :: Ptr CValType_ -> IO CBool

foreign import ccall unsafe "hs_WasmEdge_ValTypeIsFuncRef"
  c_ValTypeIsFuncRef :: Ptr CValType_ -> IO CBool

foreign import ccall unsafe "hs_WasmEdge_ValTypeIsExternRef"
  c_ValTypeIsExternRef :: Ptr CValType_ -> IO CBool

foreign import ccall unsafe "hs_WasmEdge_ValTypeIsRef"
  c_ValTypeIsRef :: Ptr CValType_ -> IO CBool

foreign import ccall unsafe "hs_WasmEdge_ValTypeIsRefNull"
  c_ValTypeIsRefNull :: Ptr CValType_ -> IO CBool

-- ---------------------------------------------------------------------------
-- Value generators
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "hs_WasmEdge_ValueGenI32"
  c_ValueGenI32 :: Ptr CValue_ -> Int32 -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ValueGenI64"
  c_ValueGenI64 :: Ptr CValue_ -> Int64 -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ValueGenF32"
  c_ValueGenF32 :: Ptr CValue_ -> CFloat -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ValueGenF64"
  c_ValueGenF64 :: Ptr CValue_ -> CDouble -> IO ()

-- | Generate a V128 value from two Word64 (hi, lo).
foreign import ccall unsafe "hs_WasmEdge_ValueGenV128"
  c_ValueGenV128 :: Ptr CValue_ -> Word64 -> Word64 -> IO ()

-- | Generate a FuncRef value from a FunctionInstance pointer.
-- Passing 'nullPtr' generates a null FuncRef.
foreign import ccall unsafe "hs_WasmEdge_ValueGenFuncRef"
  c_ValueGenFuncRef :: Ptr CValue_ -> Ptr FunctionInstanceTag -> IO ()

-- | Generate an ExternRef value from an arbitrary Haskell pointer.
foreign import ccall unsafe "hs_WasmEdge_ValueGenExternRef"
  c_ValueGenExternRef :: Ptr CValue_ -> Ptr () -> IO ()

-- | Generate a null FuncRef value.
foreign import ccall unsafe "hs_WasmEdge_ValueGenNullFuncRef"
  c_ValueGenNullFuncRef :: Ptr CValue_ -> IO ()

-- | Generate a null ExternRef value.
foreign import ccall unsafe "hs_WasmEdge_ValueGenNullExternRef"
  c_ValueGenNullExternRef :: Ptr CValue_ -> IO ()

-- ---------------------------------------------------------------------------
-- Value extractors
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "hs_WasmEdge_ValueGetI32"
  c_ValueGetI32 :: Ptr CValue_ -> IO Int32

foreign import ccall unsafe "hs_WasmEdge_ValueGetI64"
  c_ValueGetI64 :: Ptr CValue_ -> IO Int64

foreign import ccall unsafe "hs_WasmEdge_ValueGetF32"
  c_ValueGetF32 :: Ptr CValue_ -> IO CFloat

foreign import ccall unsafe "hs_WasmEdge_ValueGetF64"
  c_ValueGetF64 :: Ptr CValue_ -> IO CDouble

-- | Retrieve V128 as two Word64 (hi, lo) written to output pointers.
foreign import ccall unsafe "hs_WasmEdge_ValueGetV128"
  c_ValueGetV128 :: Ptr CValue_ -> Ptr Word64 -> Ptr Word64 -> IO ()

foreign import ccall unsafe "hs_WasmEdge_ValueIsNullRef"
  c_ValueIsNullRef :: Ptr CValue_ -> IO CBool

-- | Get the FunctionInstance pointer from a FuncRef value.
-- Returns 'nullPtr' for a null FuncRef.
foreign import ccall unsafe "hs_WasmEdge_ValueGetFuncRef"
  c_ValueGetFuncRef :: Ptr CValue_ -> IO (Ptr FunctionInstanceTag)

-- | Get the ExternRef pointer from an ExternRef value.
foreign import ccall unsafe "hs_WasmEdge_ValueGetExternRef"
  c_ValueGetExternRef :: Ptr CValue_ -> IO (Ptr ())

-- | Get the ValType of a value (written to out pointer).
foreign import ccall unsafe "hs_WasmEdge_ValueGetType"
  c_ValueGetType :: Ptr CValue_ -> Ptr CValType_ -> IO ()

-- ---------------------------------------------------------------------------
-- Value array helpers
-- ---------------------------------------------------------------------------

-- | Allocate a C heap array of n WasmEdge_Value structs. Caller must free.
foreign import ccall unsafe "hs_WasmEdge_ValueArrayAlloc"
  c_ValueArrayAlloc :: Word32 -> IO (Ptr CValue_)

-- | Free an array allocated by 'c_ValueArrayAlloc'.
foreign import ccall unsafe "hs_WasmEdge_ValueArrayFree"
  c_ValueArrayFree :: Ptr CValue_ -> IO ()

-- | Set arr[idx] from a value pointer.
foreign import ccall unsafe "hs_WasmEdge_ValueArraySet"
  c_ValueArraySet :: Ptr CValue_ -> Word32 -> Ptr CValue_ -> IO ()

-- | Get arr[idx] into an output value pointer.
foreign import ccall unsafe "hs_WasmEdge_ValueArrayGet"
  c_ValueArrayGet :: Ptr CValue_ -> Word32 -> Ptr CValue_ -> IO ()
