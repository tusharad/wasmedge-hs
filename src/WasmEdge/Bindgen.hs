{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : WasmEdge.Bindgen
Description : High-level guest function invocation and host function data marshalling
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Inspired by @wasmedge-bindgen@ in the Go and Rust SDKs, this module provides
high-level, type-safe abstractions for invoking WebAssembly guest functions
that accept and return complex data (JSON, UTF-8 strings, and raw ByteStrings)
without requiring manual pointer arithmetic or allocation management.

== Calling Guest Functions

@
import WasmEdge
import WasmEdge.Bindgen
import Data.Aeson (FromJSON, ToJSON)

data MyRequest = MyRequest { query :: Text } deriving (Generic, ToJSON)
data MyResponse = MyResponse { hits :: [Text] } deriving (Generic, FromJSON)

-- Single-line guest invocation:
response <- callGuestJson vm "search_module" "execute_search" (MyRequest "example")
case response of
  Left err  -> putStrLn $ "Error: " ++ show err
  Right res -> print (hits res)
@

== Reading and Writing from Host Functions

When a host function is invoked by the guest, it receives a 'CallingFrame'.
This module provides helpers to read and write strings and JSON directly:

@
myHostLog :: CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal])
myHostLog frame [WasmI32 ptr, WasmI32 len] = do
  res <- callerReadText frame (fromIntegral ptr) (fromIntegral len)
  case res of
    Left err  -> pure (Left err)
    Right msg -> do
      putStrLn $ "Guest log: " ++ show msg
      pure (Right [])
@
-}
module WasmEdge.Bindgen
  ( -- * High-Level Guest Invocation
    callGuestJson
  , callGuestJson2
  , callGuestBytes
  , callGuestText
  , callGuest

    -- * Host Function CallingFrame Helpers
  , callerReadText
  , callerWriteText
  , callerReadJson
  , callerWriteJson
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson qualified as Aeson
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word32)

import WasmEdge.Caller (readCallerMemory, writeCallerMemory)
import WasmEdge.Error (ErrCategory (..), WasmEdgeError (..))
import WasmEdge.Function (CallingFrame)
import WasmEdge.Memory.Alloc (defaultConvention, withWasmBuffer, withWasmBuffer2)
import WasmEdge.Memory.Codec (WasmMemory (..))
import WasmEdge.VM (VM)

-- -----------------------------------------------------------------------------
-- High-Level Guest Invocation
-- -----------------------------------------------------------------------------

{- | Call a guest function with a JSON serializable value, returning a JSON
decoded value.

The guest function must follow the standard allocation convention (@alloc@,
@dealloc@) and accept @(ptr, len)@ and return @(ptr, len)@ packed into an @i64@
or separate @i32@s.
-}
callGuestJson ::
  (ToJSON a, FromJSON b) =>
  VM ->
  Text ->
  Text ->
  a ->
  IO (Either WasmEdgeError b)
callGuestJson vm modName funcName inputVal = do
  let jsonBytes = BSL.toStrict (Aeson.encode inputVal)
  rawRes <- callGuestBytes vm modName funcName jsonBytes
  case rawRes of
    Left err -> pure (Left err)
    Right outBytes ->
      case Aeson.eitherDecodeStrict' outBytes of
        Left parseErr ->
          pure $
            Left
              ( WasmEdgeError
                  ErrCategory_UserDefined
                  1
                  ("JSON decode error from guest: " <> T.pack parseErr)
              )
        Right val -> pure (Right val)

{- | Call a guest function with two JSON serializable values, returning a JSON
decoded value.
-}
callGuestJson2 ::
  (ToJSON a, ToJSON b, FromJSON r) =>
  VM ->
  Text ->
  Text ->
  a ->
  b ->
  IO (Either WasmEdgeError r)
callGuestJson2 vm modName funcName in1 in2 = do
  let bs1 = BSL.toStrict (Aeson.encode in1)
      bs2 = BSL.toStrict (Aeson.encode in2)
  res <- withWasmBuffer2 vm modName funcName defaultConvention bs1 bs2
  case res of
    Left err -> pure (Left err)
    Right outBytes ->
      case Aeson.eitherDecodeStrict' outBytes of
        Left parseErr ->
          pure $
            Left
              ( WasmEdgeError
                  ErrCategory_UserDefined
                  1
                  ("JSON decode error from guest: " <> T.pack parseErr)
              )
        Right val -> pure (Right val)

-- | Call a guest function with a raw 'ByteString', returning a 'ByteString'.
callGuestBytes ::
  VM ->
  Text ->
  Text ->
  ByteString ->
  IO (Either WasmEdgeError ByteString)
callGuestBytes vm modName funcName =
  withWasmBuffer vm modName funcName defaultConvention

-- | Call a guest function with a UTF-8 'Text', returning a UTF-8 'Text'.
callGuestText ::
  VM ->
  Text ->
  Text ->
  Text ->
  IO (Either WasmEdgeError Text)
callGuestText vm modName funcName =
  withWasmBuffer vm modName funcName defaultConvention

-- | Call a guest function with any type implementing 'WasmMemory'.
callGuest ::
  (WasmMemory a, WasmMemory b) =>
  VM ->
  Text ->
  Text ->
  a ->
  IO (Either WasmEdgeError b)
callGuest vm modName funcName =
  withWasmBuffer vm modName funcName defaultConvention

-- -----------------------------------------------------------------------------
-- Host Function CallingFrame Helpers
-- -----------------------------------------------------------------------------

-- | Read a UTF-8 string from the calling guest's linear memory at the specified offset and length.
callerReadText ::
  CallingFrame ->
  Word32 ->
  Word32 ->
  IO (Either WasmEdgeError Text)
callerReadText frame offset len = do
  mBs <- readCallerMemory frame 0 offset len
  case mBs of
    Nothing ->
      pure $
        Left (WasmEdgeError ErrCategory_UserDefined 1 "Failed to read memory from calling frame")
    Just bs ->
      case TE.decodeUtf8' bs of
        Left utfErr ->
          pure $
            Left
              ( WasmEdgeError
                  ErrCategory_UserDefined
                  2
                  ("UTF-8 decoding error in caller memory: " <> T.pack (show utfErr))
              )
        Right txt -> pure (Right txt)

{- | Write a UTF-8 string into the calling guest's linear memory at the specified offset.
Returns the number of bytes written.
-}
callerWriteText ::
  CallingFrame ->
  Word32 ->
  Text ->
  IO (Either WasmEdgeError Word32)
callerWriteText frame offset txt = do
  let bs = TE.encodeUtf8 txt
      len = fromIntegral (BS.length bs)
  res <- writeCallerMemory frame 0 offset bs
  case res of
    Left err -> pure (Left err)
    Right () -> pure (Right len)

-- | Read and decode a JSON value from the calling guest's linear memory.
callerReadJson ::
  FromJSON a =>
  CallingFrame ->
  Word32 ->
  Word32 ->
  IO (Either WasmEdgeError a)
callerReadJson frame offset len = do
  mBs <- readCallerMemory frame 0 offset len
  case mBs of
    Nothing ->
      pure $
        Left (WasmEdgeError ErrCategory_UserDefined 1 "Failed to read memory from calling frame")
    Just bs ->
      case Aeson.eitherDecodeStrict' bs of
        Left parseErr ->
          pure $
            Left
              ( WasmEdgeError
                  ErrCategory_UserDefined
                  3
                  ("JSON decode error from caller memory: " <> T.pack parseErr)
              )
        Right val -> pure (Right val)

{- | Encode and write a JSON value into the calling guest's linear memory at the specified offset.
Returns the number of bytes written.
-}
callerWriteJson ::
  ToJSON a =>
  CallingFrame ->
  Word32 ->
  a ->
  IO (Either WasmEdgeError Word32)
callerWriteJson frame offset val = do
  let bs = BSL.toStrict (Aeson.encode val)
      len = fromIntegral (BS.length bs)
  res <- writeCallerMemory frame 0 offset bs
  case res of
    Left err -> pure (Left err)
    Right () -> pure (Right len)
