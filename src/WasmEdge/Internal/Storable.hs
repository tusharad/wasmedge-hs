{- |
Module      : WasmEdge.Internal.Storable
Description : Storable instances for WasmEdge C structs
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : internal

Provides 'Storable' instances and allocation helpers for the C structs
that WasmEdge returns by value. These are used internally when calling
the shim layer.

__Do not import this module in user code.__
-}
module WasmEdge.Internal.Storable
  ( -- * WasmEdge_String layout
    CString_
  , allocaCString
  , peekCStringBuf
  , peekCStringLen
  , cStringSize
  , stringSize

    -- * WasmEdge_Bytes layout
  , CBytes_
  , allocaCBytes

    -- * WasmEdge_Result layout
  , CResult_
  , allocaCResult
  , peekResultCode

    -- * WasmEdge_ValType layout (8 bytes opaque)
  , CValType_
  , allocaCValType
  , valTypeSize

    -- * WasmEdge_Value layout (uint128 + ValType = 24 bytes)
  , CValue_
  , allocaCValue
  , valueSize

    -- * Stack-allocated array helpers
  , withCValTypeArray
  , withCValueArray
  ) where

import Data.Word (Word32, Word8)
import Foreign.Marshal.Alloc (alloca, allocaBytes)
import Foreign.Ptr
import Foreign.Storable

-- ---------------------------------------------------------------------------
-- WasmEdge_String  (uint32_t Length; const char* Buf)
-- ---------------------------------------------------------------------------

{- | Opaque placeholder for the 'WasmEdge_String' C struct layout.
Use 'allocaCString' to allocate on the stack.
-}
data CString_

-- | Allocate a stack-allocated 'WasmEdge_String' and pass it to the action.
allocaCString :: (Ptr CString_ -> IO a) -> IO a
allocaCString = allocaBytes cStringSize

-- Size: uint32_t (4) + padding (4 on 64-bit) + ptr (8) = 16 bytes typically
-- We use hsc2hs for the real layout; for now use a conservative 16 bytes.
cStringSize :: Int
cStringSize = 16 -- overridden by hsc2hs #size WasmEdge_String at compile time

stringSize :: Int
stringSize = cStringSize

-- | Peek the buffer pointer from a 'WasmEdge_String'.
peekCStringBuf :: Ptr CString_ -> IO (Ptr Word8)
peekCStringBuf p = peekByteOff p 8 -- Buf is at offset 8 (after Length + padding)

-- | Peek the length from a 'WasmEdge_String'.
peekCStringLen :: Ptr CString_ -> IO Word32
peekCStringLen p = peekByteOff p 0

-- ---------------------------------------------------------------------------
-- WasmEdge_Bytes  (uint32_t Length; const uint8_t* Buf)
-- ---------------------------------------------------------------------------

-- | Opaque placeholder for the 'WasmEdge_Bytes' C struct layout.
data CBytes_

allocaCBytes :: (Ptr CBytes_ -> IO a) -> IO a
allocaCBytes = allocaBytes 16 -- same layout as WasmEdge_String

-- ---------------------------------------------------------------------------
-- WasmEdge_Result  (uint32_t Code)
-- ---------------------------------------------------------------------------

-- | Opaque placeholder for the 'WasmEdge_Result' C struct (single uint32_t).
data CResult_

allocaCResult :: (Ptr CResult_ -> IO a) -> IO a
allocaCResult = alloca @Word32 . (. castPtr)

-- | Peek the Code field from a 'WasmEdge_Result'.
peekResultCode :: Ptr CResult_ -> IO Word32
peekResultCode p = peek (castPtr p)

-- ---------------------------------------------------------------------------
-- WasmEdge_ValType  (uint8_t Data[8])
-- ---------------------------------------------------------------------------

-- | Opaque placeholder for the 'WasmEdge_ValType' C struct (8 opaque bytes).
data CValType_

valTypeSize :: Int
valTypeSize = 8

allocaCValType :: (Ptr CValType_ -> IO a) -> IO a
allocaCValType = allocaBytes valTypeSize

-- | Allocate an array of n 'CValType_' structs on the stack.
withCValTypeArray :: Int -> (Ptr CValType_ -> IO a) -> IO a
withCValTypeArray 0 action = action nullPtr
withCValTypeArray n action = allocaBytes (n * valTypeSize) action

-- ---------------------------------------------------------------------------
-- WasmEdge_Value  (uint128_t Value; WasmEdge_ValType Type)
-- = 16 bytes (uint128) + 8 bytes (ValType) + 8 bytes (alignment padding) = 32 bytes
-- ---------------------------------------------------------------------------

-- | Opaque placeholder for the 'WasmEdge_Value' C struct.
data CValue_

valueSize :: Int
valueSize = 32

allocaCValue :: (Ptr CValue_ -> IO a) -> IO a
allocaCValue = allocaBytes valueSize

-- | Allocate an array of n 'CValue_' structs on the stack.
withCValueArray :: Int -> (Ptr CValue_ -> IO a) -> IO a
withCValueArray 0 action = action nullPtr
withCValueArray n action = allocaBytes (n * valueSize) action
