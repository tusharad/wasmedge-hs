-- |
-- Module      : WasmEdge.Caller
-- Description : Caller context and guest memory access for host functions
-- Copyright   : (c) 2026 Tushar Adhatrao
-- License     : MIT
-- Stability   : stable
--
-- Inspired by the @Caller@ abstraction in @wasmedge-sdk@ (Rust), this module
-- provides safe, idiomatic Haskell helpers for host functions to inspect and
-- manipulate the linear memory of the calling WebAssembly guest instance.
--
-- When a WebAssembly module invokes an imported host function, WasmEdge supplies
-- a 'CallingFrame'. Using 'getCallerMemory', 'readCallerMemory', or 'writeCallerMemory',
-- host functions can easily exchange structured data, buffers, and strings with the guest.
--
-- == Example
--
-- @
-- import WasmEdge.Caller
-- import qualified Data.ByteString as BS
--
-- -- Host function reading a string from guest memory and logging it
-- logMessageHostFunc :: CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal])
-- logMessageHostFunc frame [WasmI32 ptr, WasmI32 len] = do
--   mStr <- readCallerMemory frame 0 (fromIntegral ptr) (fromIntegral len)
--   case mStr of
--     Nothing -> pure (Left (WasmEdgeError ErrCategory_UserDefined 1 "Invalid memory access"))
--     Just bs -> do
--       putStrLn $ "Guest message: " ++ show bs
--       pure (Right [])
-- logMessageHostFunc _ _ = pure (Left (WasmEdgeError ErrCategory_UserDefined 2 "Invalid arguments"))
-- @
module WasmEdge.Caller
  ( -- * Caller memory access
    getCallerMemory
  , readCallerMemory
  , writeCallerMemory
  , readCallerCString
  , readCallerCStringMax

    -- * Caller execution context
  , getCallerModuleInstance
  , getCallerExecutor
  ) where

import Data.ByteString       (ByteString)
import qualified Data.ByteString        as BS
import Foreign.Ptr           (Ptr, nullPtr, castPtr)
import Data.Word             (Word32)

import WasmEdge.Error        (WasmEdgeError (..), ErrCategory (..), WasmResult)
import WasmEdge.Function     (CallingFrame (..), callingFrameGetMemoryInstance, callingFrameGetModuleInstance, callingFrameGetExecutor)
import WasmEdge.Memory       (MemoryInstance, borrowMemory, getMemoryData, setMemoryData, getMemoryPageSize, getMemoryPointerConst)
import WasmEdge.Internal.Types (ModuleInstanceTag, ExecutorTag)

-- | Borrow the 'MemoryInstance' at the given index from the caller module.
--
-- In WebAssembly, index 0 is the default linear memory.
-- Returns 'Nothing' if the caller module has no memory at that index or if the
-- calling frame is invalid.
getCallerMemory :: CallingFrame -> Word32 -> IO (Maybe MemoryInstance)
getCallerMemory frame idx = do
  p <- callingFrameGetMemoryInstance frame idx
  if p == nullPtr
    then pure Nothing
    else Just <$> borrowMemory p

-- | Read @length@ bytes from the caller's linear memory at index @memIdx@ starting at @offset@.
-- Returns 'Nothing' if the memory instance cannot be found or the range is out of bounds.
readCallerMemory
  :: CallingFrame -- ^ Calling frame passed to host function
  -> Word32       -- ^ Memory index (typically 0)
  -> Word32       -- ^ Byte offset in memory
  -> Word32       -- ^ Number of bytes to read
  -> IO (Maybe ByteString)
readCallerMemory frame memIdx offset len = do
  mMem <- getCallerMemory frame memIdx
  case mMem of
    Nothing  -> pure Nothing
    Just mem -> do
      res <- getMemoryData mem offset len
      case res of
        Left _   -> pure Nothing
        Right bs -> pure (Just bs)

-- | Write a 'ByteString' into the caller's linear memory at index @memIdx@ starting at @offset@.
writeCallerMemory
  :: CallingFrame -- ^ Calling frame passed to host function
  -> Word32       -- ^ Memory index (typically 0)
  -> Word32       -- ^ Byte offset in memory
  -> ByteString   -- ^ Bytes to write
  -> IO (WasmResult ())
writeCallerMemory frame memIdx offset bs = do
  mMem <- getCallerMemory frame memIdx
  case mMem of
    Nothing  -> pure (Left (WasmEdgeError ErrCategory_WASM 0x01 "Caller memory instance not found"))
    Just mem -> setMemoryData mem offset bs

-- | Read a null-terminated UTF-8 / ASCII string from caller memory starting at @offset@,
-- scanning up to 4096 bytes.
readCallerCString
  :: CallingFrame -- ^ Calling frame passed to host function
  -> Word32       -- ^ Memory index (typically 0)
  -> Word32       -- ^ Byte offset in memory
  -> IO (Maybe ByteString)
readCallerCString frame memIdx offset = readCallerCStringMax frame memIdx offset 4096

-- | Read a null-terminated string from caller memory with an explicit upper bound on bytes scanned.
readCallerCStringMax
  :: CallingFrame -- ^ Calling frame
  -> Word32       -- ^ Memory index (typically 0)
  -> Word32       -- ^ Byte offset in memory
  -> Word32       -- ^ Maximum bytes to scan
  -> IO (Maybe ByteString)
readCallerCStringMax frame memIdx offset maxScan = do
  mMem <- getCallerMemory frame memIdx
  case mMem of
    Nothing  -> pure Nothing
    Just mem -> do
      pageSize <- getMemoryPageSize mem
      let totalBytes = pageSize * 65536
      if offset >= totalBytes
        then pure Nothing
        else do
          let boundedLen = min maxScan (totalBytes - offset)
          ptr <- getMemoryPointerConst mem offset boundedLen
          if ptr == nullPtr
            then pure Nothing
            else do
              bs <- BS.packCString (castPtr ptr)
              pure (Just bs)

-- | Retrieve the raw module instance pointer of the current calling frame.
getCallerModuleInstance :: CallingFrame -> IO (Ptr ModuleInstanceTag)
getCallerModuleInstance = callingFrameGetModuleInstance

-- | Retrieve the raw executor pointer from the current calling frame.
getCallerExecutor :: CallingFrame -> IO (Ptr ExecutorTag)
getCallerExecutor = callingFrameGetExecutor
