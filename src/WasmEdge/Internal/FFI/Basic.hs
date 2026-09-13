{-# LANGUAGE ForeignFunctionInterface #-}

{- |
Module      : WasmEdge.Internal.FFI.Basic
Description : Raw FFI bindings for WasmEdge basic types: version, string, bytes, result, log
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : internal

Direct 'foreign import' declarations for all WasmEdge basic C API functions,
via the @cbits/wasmedge_hs_shims.c@ shim layer. All struct-by-value returns
have been converted to out-pointer style.

__Do not import this module in user code.__
-}
module WasmEdge.Internal.FFI.Basic
  ( -- * Version
    c_VersionGet
  , c_VersionGetMajor
  , c_VersionGetMinor
  , c_VersionGetPatch

    -- * Logging
  , c_LogSetErrorLevel
  , c_LogSetDebugLevel
  , c_LogOff
  , c_LogSetLevel
  , c_LogSetCallback

    -- * String (via shims)
  , c_StringCreateByCString
  , c_StringCreateByBuffer
  , c_StringWrap
  , c_StringIsEqual
  , c_StringCopy
  , c_StringDelete
  , c_StringGetLength
  , c_StringGetBuf

    -- * Bytes (via shims)
  , c_BytesCreate
  , c_BytesWrap
  , c_BytesDelete
  , c_BytesGetLength
  , c_BytesGetBuf

    -- * Result (via shims)
  , c_Result_Success
  , c_Result_Terminate
  , c_Result_Fail
  , c_ResultOK
  , c_ResultGen
  , c_ResultGetCode
  , c_ResultGetCategory
  , c_ResultGetMessage

    -- * Raw callback type
  , RawLogCallbackT
  , mkLogCallback
  ) where

import Data.Word (Word32, Word8)
import Foreign.C
import Foreign.Ptr

import WasmEdge.Internal.Storable (CBytes_, CResult_, CString_)

-- ---------------------------------------------------------------------------
-- Version functions
-- ---------------------------------------------------------------------------

{- | Get the version string of the WasmEdge C API (e.g., @\"0.18.0\"@).
The returned pointer points to a static string — do NOT free it.
-}
foreign import ccall unsafe "WasmEdge_VersionGet"
  c_VersionGet :: IO CString

-- | Get the major version number.
foreign import ccall unsafe "WasmEdge_VersionGetMajor"
  c_VersionGetMajor :: IO Word32

-- | Get the minor version number.
foreign import ccall unsafe "WasmEdge_VersionGetMinor"
  c_VersionGetMinor :: IO Word32

-- | Get the patch version number.
foreign import ccall unsafe "WasmEdge_VersionGetPatch"
  c_VersionGetPatch :: IO Word32

-- ---------------------------------------------------------------------------
-- Logging functions
-- ---------------------------------------------------------------------------

-- | Set the logging system to filter to error level only.
foreign import ccall unsafe "WasmEdge_LogSetErrorLevel"
  c_LogSetErrorLevel :: IO ()

-- | Set the logging system to filter to debug level (verbose).
foreign import ccall unsafe "WasmEdge_LogSetDebugLevel"
  c_LogSetDebugLevel :: IO ()

-- | Turn off all logging output.
foreign import ccall unsafe "WasmEdge_LogOff"
  c_LogOff :: IO ()

{- | Set the log level to a specific 'Word32' value (maps to 'WasmEdge_LogLevel' enum).
Use the 'WasmEdge.Log.LogLevel' type and 'logLevelToC' for safe access.
-}
foreign import ccall unsafe "WasmEdge_LogSetLevel"
  c_LogSetLevel :: Word32 -> IO ()

{- | The raw C type of a log callback:
@void callback(const WasmEdge_LogMessage *msg)@

We represent the message pointer as 'Ptr ()' since hsc2hs will resolve
the exact struct layout separately. Users should use the public
'WasmEdge.Log.setLogCallback' API instead of this raw import.
-}
type RawLogCallbackT = Ptr () -> IO ()

foreign import ccall unsafe "wrapper"
  mkLogCallback :: RawLogCallbackT -> IO (FunPtr RawLogCallbackT)

-- | Set a custom log callback (safe: callback may call back into Haskell).
foreign import ccall safe "WasmEdge_LogSetCallback"
  c_LogSetCallback :: FunPtr RawLogCallbackT -> IO ()

-- ---------------------------------------------------------------------------
-- String functions (via shims — all take/return Ptr CString_)
-- ---------------------------------------------------------------------------

{- | Create a WasmEdge_String from a NULL-terminated C string.
Caller owns the result; call 'c_StringDelete' to free.
-}
foreign import ccall unsafe "hs_WasmEdge_StringCreateByCString"
  c_StringCreateByCString :: Ptr CString_ -> CString -> IO ()

{- | Create a WasmEdge_String from a buffer with explicit length.
Caller owns the result; call 'c_StringDelete' to free.
-}
foreign import ccall unsafe "hs_WasmEdge_StringCreateByBuffer"
  c_StringCreateByBuffer :: Ptr CString_ -> CString -> Word32 -> IO ()

-- | Wrap a buffer as a WasmEdge_String (no copy; DO NOT call 'c_StringDelete').
foreign import ccall unsafe "hs_WasmEdge_StringWrap"
  c_StringWrap :: Ptr CString_ -> CString -> Word32 -> IO ()

-- | Compare two WasmEdge_String objects for equality.
foreign import ccall unsafe "hs_WasmEdge_StringIsEqual"
  c_StringIsEqual :: Ptr CString_ -> Ptr CString_ -> IO CBool

-- | Copy the content of a WasmEdge_String into a buffer.
foreign import ccall unsafe "hs_WasmEdge_StringCopy"
  c_StringCopy :: Ptr CString_ -> CString -> Word32 -> IO Word32

-- | Delete (free) a WasmEdge_String created by 'c_StringCreateBy*'.
foreign import ccall unsafe "hs_WasmEdge_StringDelete"
  c_StringDelete :: Ptr CString_ -> IO ()

-- | Get the length of a WasmEdge_String.
foreign import ccall unsafe "hs_WasmEdge_StringGetLength"
  c_StringGetLength :: Ptr CString_ -> IO Word32

-- | Get the const char* buffer of a WasmEdge_String.
foreign import ccall unsafe "hs_WasmEdge_StringGetBuf"
  c_StringGetBuf :: Ptr CString_ -> IO CString

-- ---------------------------------------------------------------------------
-- Bytes functions (via shims)
-- ---------------------------------------------------------------------------

{- | Create a WasmEdge_Bytes from a buffer (copies the data).
Caller owns the result; call 'c_BytesDelete' to free.
-}
foreign import ccall unsafe "hs_WasmEdge_BytesCreate"
  c_BytesCreate :: Ptr CBytes_ -> Ptr Word8 -> Word32 -> IO ()

-- | Wrap a buffer as WasmEdge_Bytes (no copy; DO NOT call 'c_BytesDelete').
foreign import ccall unsafe "hs_WasmEdge_BytesWrap"
  c_BytesWrap :: Ptr CBytes_ -> Ptr Word8 -> Word32 -> IO ()

-- | Delete a WasmEdge_Bytes created by 'c_BytesCreate'.
foreign import ccall unsafe "hs_WasmEdge_BytesDelete"
  c_BytesDelete :: Ptr CBytes_ -> IO ()

-- | Get the length of a WasmEdge_Bytes.
foreign import ccall unsafe "hs_WasmEdge_BytesGetLength"
  c_BytesGetLength :: Ptr CBytes_ -> IO Word32

-- | Get the const uint8_t* buffer of a WasmEdge_Bytes.
foreign import ccall unsafe "hs_WasmEdge_BytesGetBuf"
  c_BytesGetBuf :: Ptr CBytes_ -> IO (Ptr Word8)

-- ---------------------------------------------------------------------------
-- Result functions (via shims)
-- ---------------------------------------------------------------------------

-- | Fill a CResult_ with the Success code (0x00).
foreign import ccall unsafe "hs_WasmEdge_Result_Success"
  c_Result_Success :: Ptr CResult_ -> IO ()

-- | Fill a CResult_ with the Terminate code (0x01).
foreign import ccall unsafe "hs_WasmEdge_Result_Terminate"
  c_Result_Terminate :: Ptr CResult_ -> IO ()

-- | Fill a CResult_ with the Fail code (0x02).
foreign import ccall unsafe "hs_WasmEdge_Result_Fail"
  c_Result_Fail :: Ptr CResult_ -> IO ()

-- | Check whether a CResult_ represents success (Success or Terminate).
foreign import ccall unsafe "hs_WasmEdge_ResultOK"
  c_ResultOK :: Ptr CResult_ -> IO CBool

{- | Generate a result with a specific error category and code.
Category is a Word32 mapping to 'WasmEdge_ErrCategory'.
-}
foreign import ccall unsafe "hs_WasmEdge_ResultGen"
  c_ResultGen :: Ptr CResult_ -> Word32 -> Word32 -> IO ()

-- | Get the 24-bit error code from a CResult_.
foreign import ccall unsafe "hs_WasmEdge_ResultGetCode"
  c_ResultGetCode :: Ptr CResult_ -> IO Word32

-- | Get the error category as a Word32.
foreign import ccall unsafe "hs_WasmEdge_ResultGetCategory"
  c_ResultGetCategory :: Ptr CResult_ -> IO Word32

-- | Get the error message as a static C string (do NOT free).
foreign import ccall unsafe "hs_WasmEdge_ResultGetMessage"
  c_ResultGetMessage :: Ptr CResult_ -> IO CString
