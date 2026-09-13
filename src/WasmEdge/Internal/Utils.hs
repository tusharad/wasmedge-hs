{- |
Module      : WasmEdge.Internal.Utils
Description : Internal utility functions shared across FFI modules
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : internal

__Do not import this module in user code.__
-}
module WasmEdge.Internal.Utils
  ( -- * Text / String conversion
    withWasmString
  , fromWasmString
  , peekWasmString
  , withWasmBytes

    -- * Checked result conversion
  , checkResult
  , throwOnFail

    -- * Pointer utilities
  , maybeNullPtr
  , fromNullablePtr
  ) where

import Control.Exception (throwIO)
import Data.ByteString qualified as BS
import Data.ByteString.Unsafe qualified as UBS
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Foreign.C (CBool (..))
import Foreign.C.String (peekCString)
import Foreign.Ptr (Ptr, castPtr, nullPtr)

import WasmEdge.Error (WasmEdgeError (..), mkErrCategory)
import WasmEdge.Internal.FFI.Basic
  ( c_BytesWrap
  , c_ResultGetCategory
  , c_ResultGetCode
  , c_ResultGetMessage
  , c_ResultOK
  , c_StringCreateByBuffer
  , c_StringDelete
  , c_StringGetBuf
  , c_StringGetLength
  )
import WasmEdge.Internal.Storable

-- ---------------------------------------------------------------------------
-- Text <-> WasmEdge_String
-- ---------------------------------------------------------------------------

{- | Convert a Haskell 'Text' to a 'WasmEdge_String' (on the stack),
call the action, then delete the string.
-}
withWasmString :: Text -> (Ptr CString_ -> IO a) -> IO a
withWasmString t action =
  BS.useAsCStringLen (TE.encodeUtf8 t) $ \(buf, len) ->
    allocaCString $ \strPtr -> do
      c_StringCreateByBuffer strPtr buf (fromIntegral len)
      result <- action strPtr
      c_StringDelete strPtr
      pure result

{- | Peek a 'WasmEdge_String' (by pointer) and convert to Haskell 'Text'.
Does NOT free the string.
-}
peekWasmString :: Ptr CString_ -> IO Text
peekWasmString strPtr = do
  len <- c_StringGetLength strPtr
  buf <- c_StringGetBuf strPtr
  if buf == nullPtr || len == 0
    then pure mempty
    else do
      bs <- BS.packCStringLen (buf, fromIntegral len)
      pure (TE.decodeUtf8Lenient bs)

-- | Alias for 'peekWasmString' — reads a WasmEdge_String and returns Text.
fromWasmString :: Ptr CString_ -> IO Text
fromWasmString = peekWasmString

{- | Wrap a 'BS.ByteString' as a stack-allocated 'WasmEdge_Bytes' (zero copy),
call the action, and return its result.
-}
withWasmBytes :: BS.ByteString -> (Ptr CBytes_ -> IO a) -> IO a
withWasmBytes bs action =
  UBS.unsafeUseAsCStringLen bs $ \(buf, len) ->
    allocaCBytes $ \bytesPtr -> do
      c_BytesWrap bytesPtr (castPtr buf) (fromIntegral len)
      action bytesPtr

-- ---------------------------------------------------------------------------
-- Result checking
-- ---------------------------------------------------------------------------

{- | Check a 'WasmEdge_Result' pointer and return 'Right ()' on success
or 'Left WasmEdgeError' on failure.
-}
checkResult :: Ptr CResult_ -> IO (Either WasmEdgeError ())
checkResult resPtr = do
  CBool ok <- c_ResultOK resPtr
  if ok /= 0
    then pure (Right ())
    else do
      code <- c_ResultGetCode resPtr
      category <- c_ResultGetCategory resPtr
      msgPtr <- c_ResultGetMessage resPtr
      msg <-
        if msgPtr == nullPtr
          then pure "unknown error"
          else T.pack <$> peekCString msgPtr
      pure $
        Left
          WasmEdgeError
            { weErrCategory = mkErrCategory category
            , weErrCode = code
            , weErrMessage = msg
            }

-- | Like 'checkResult', but throws 'WasmEdgeError' on failure.
throwOnFail :: Ptr CResult_ -> IO ()
throwOnFail resPtr =
  checkResult resPtr >>= \case
    Right () -> pure ()
    Left err -> throwIO err

-- ---------------------------------------------------------------------------
-- Pointer utilities
-- ---------------------------------------------------------------------------

-- | Convert a 'Maybe (Ptr t)' to a nullable C pointer.
maybeNullPtr :: Maybe (Ptr t) -> Ptr t
maybeNullPtr = fromMaybe nullPtr

-- | Convert a nullable C pointer to 'Maybe'.
fromNullablePtr :: Ptr t -> Maybe (Ptr t)
fromNullablePtr p
  | p == nullPtr = Nothing
  | otherwise = Just p
