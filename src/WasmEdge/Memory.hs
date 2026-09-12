-- |
-- Module      : WasmEdge.Memory
-- Description : WasmEdge linear memory contexts
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : stable
--
-- Provides types and functions for inspecting and manipulating WebAssembly
-- linear memory instances:
--
-- * 'MemoryType' — describes the page limits of a linear memory
-- * 'MemoryInstance' — a runtime linear memory instance with byte-level read/write
module WasmEdge.Memory
  ( -- * Memory type
    MemoryType
  , createMemoryType
  , deleteMemoryType
  , withMemoryType
  , getMemoryTypeLimit

    -- * Memory instance
  , MemoryInstance
  , createMemory
  , deleteMemory
  , withMemory
  , getMemoryType
  , getMemoryData
  , setMemoryData
  , getMemoryPointer
  , getMemoryPointerConst
  , getMemoryPageSize
  , growMemoryPages

    -- * Internal / borrowed pointers
  , unsafeMemoryPtr
  , borrowMemory
  , unsafeMemoryTypePtr
  , borrowMemoryType
  , disarmMemory
  ) where

import Control.Exception     (bracket, throwIO)
import Data.ByteString       (ByteString)
import qualified Data.ByteString        as BS
import qualified Data.ByteString.Unsafe as UBS
import Foreign.C             (CBool (..))
import Foreign.Marshal.Alloc (alloca, allocaBytes)
import Foreign.Ptr           (Ptr, FunPtr, nullPtr, castPtr)
import Foreign.Storable      (peek)
import Data.Word             (Word8, Word32)

import WasmEdge.Types
import WasmEdge.Error
import WasmEdge.Internal.Types     (MemoryTypeTag, MemoryInstanceTag)
import WasmEdge.Internal.Ownership (OwnedCtx, mkOwned, withOwned, finalizeOwned, disarmOwned)
import WasmEdge.Internal.Storable  (allocaCResult)
import WasmEdge.Internal.Utils     (checkResult)
import WasmEdge.Internal.FFI.Instance

-- ---------------------------------------------------------------------------
-- MemoryType
-- ---------------------------------------------------------------------------

-- | A WebAssembly linear memory type, specifying min/max page limits.
newtype MemoryType = MemoryType (OwnedCtx MemoryTypeTag)

-- | Create a 'MemoryType' with the given 'Limit'.
-- 1 page = 64 KiB (65,536 bytes).
createMemoryType :: Limit -> IO MemoryType
createMemoryType lim = do
  let hasMax  = CBool (case limitMax lim of Just _ -> 1; Nothing -> 0)
      minPage = fromIntegral (limitMin lim)
      maxPage = case limitMax lim of Just m -> fromIntegral m; Nothing -> 0
      shared  = CBool (if limitShared lim then 1 else 0)
      is64    = CBool 0
  p <- c_MemoryTypeCreate hasMax minPage maxPage shared is64
  if p == nullPtr
    then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_MemoryTypeCreate returned NULL"
    else MemoryType <$> mkOwned (appFunPtr c_MemoryTypeDelete) p

-- | Delete a 'MemoryType'.
deleteMemoryType :: MemoryType -> IO ()
deleteMemoryType (MemoryType o) = finalizeOwned o

-- | Scoped 'MemoryType'.
withMemoryType :: Limit -> (MemoryType -> IO a) -> IO a
withMemoryType lim = bracket (createMemoryType lim) deleteMemoryType

-- | Get the 'Limit' of a 'MemoryType'.
getMemoryTypeLimit :: MemoryType -> IO Limit
getMemoryTypeLimit (MemoryType o) =
  withOwned o $ \p -> do
    limPtr <- c_MemoryTypeGetLimit p
    if limPtr == nullPtr
      then pure (Limit 0 Nothing False)
      else alloca $ \hasMaxPtr ->
           alloca $ \minPtr ->
           alloca $ \maxPtr ->
           alloca $ \sharedPtr ->
           alloca $ \is64Ptr -> do
             c_LimitGetInfo limPtr hasMaxPtr minPtr maxPtr sharedPtr is64Ptr
             CBool hasMax <- peek hasMaxPtr
             minVal       <- peek minPtr
             maxVal       <- peek maxPtr
             CBool shared <- peek sharedPtr
             pure Limit
               { limitMin    = fromIntegral minVal
               , limitMax    = if hasMax /= 0 then Just (fromIntegral maxVal) else Nothing
               , limitShared = shared /= 0
               }

-- ---------------------------------------------------------------------------
-- MemoryInstance
-- ---------------------------------------------------------------------------

-- | A runtime WebAssembly linear memory instance.
newtype MemoryInstance = MemoryInstance (OwnedCtx MemoryInstanceTag)

-- | Create a 'MemoryInstance' from a 'MemoryType'.
createMemory :: MemoryType -> IO MemoryInstance
createMemory (MemoryType mtOwned) =
  withOwned mtOwned $ \mtPtr -> do
    p <- c_MemoryInstanceCreate mtPtr
    if p == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_MemoryInstanceCreate returned NULL"
      else MemoryInstance <$> mkOwned (appFunPtr c_MemoryInstanceDelete) p

-- | Delete a 'MemoryInstance'.
deleteMemory :: MemoryInstance -> IO ()
deleteMemory (MemoryInstance o) = finalizeOwned o

-- | Scoped 'MemoryInstance'.
withMemory :: MemoryType -> (MemoryInstance -> IO a) -> IO a
withMemory mt = bracket (createMemory mt) deleteMemory

-- | Get the 'MemoryType' of a 'MemoryInstance'.
getMemoryType :: MemoryInstance -> IO MemoryType
getMemoryType (MemoryInstance o) =
  withOwned o $ \p -> do
    tp <- c_MemoryInstanceGetMemoryType p
    if tp == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_MemoryInstanceGetMemoryType returned NULL"
      else borrowMemoryType tp

-- | Read @length@ bytes from linear memory starting at @offset@.
getMemoryData :: MemoryInstance -> Word32 -> Word32 -> IO (WasmResult ByteString)
getMemoryData (MemoryInstance o) offset len =
  withOwned o $ \p ->
  allocaBytes (fromIntegral len) $ \buf ->
  allocaCResult $ \resPtr -> do
    c_MemoryInstanceGetData resPtr p (castPtr buf) offset len
    res <- checkResult resPtr
    case res of
      Left err -> pure (Left err)
      Right () -> Right <$> BS.packCStringLen (buf, fromIntegral len)

-- | Write a 'ByteString' into linear memory starting at @offset@.
setMemoryData :: MemoryInstance -> Word32 -> ByteString -> IO (WasmResult ())
setMemoryData (MemoryInstance o) offset bs =
  withOwned o $ \p ->
  UBS.unsafeUseAsCStringLen bs $ \(buf, len) ->
  allocaCResult $ \resPtr -> do
    c_MemoryInstanceSetData resPtr p (castPtr buf) offset (fromIntegral len)
    checkResult resPtr

-- | Get a direct pointer to linear memory at @offset@ for @length@ bytes.
-- The pointer is valid only as long as the memory is not grown and the instance is alive.
getMemoryPointer :: MemoryInstance -> Word32 -> Word32 -> IO (Ptr Word8)
getMemoryPointer (MemoryInstance o) offset len =
  withOwned o $ \p -> c_MemoryInstanceGetPointer p offset len

-- | Const variant of 'getMemoryPointer'.
getMemoryPointerConst :: MemoryInstance -> Word32 -> Word32 -> IO (Ptr Word8)
getMemoryPointerConst (MemoryInstance o) offset len =
  withOwned o $ \p -> c_MemoryInstanceGetPointerConst p offset len

-- | Get the current size in pages (1 page = 64 KiB).
getMemoryPageSize :: MemoryInstance -> IO Word32
getMemoryPageSize (MemoryInstance o) =
  withOwned o c_MemoryInstanceGetPageSize

-- | Grow linear memory by @pageCount@ pages.
growMemoryPages :: MemoryInstance -> Word32 -> IO (WasmResult ())
growMemoryPages (MemoryInstance o) pageCount =
  withOwned o $ \p ->
  allocaCResult $ \resPtr -> do
    c_MemoryInstanceGrowPage resPtr p pageCount
    checkResult resPtr

-- ---------------------------------------------------------------------------
-- Unsafe / internal pointer helpers
-- ---------------------------------------------------------------------------

-- | Extract the raw pointer of a 'MemoryInstance'.
unsafeMemoryPtr :: MemoryInstance -> IO (Ptr MemoryInstanceTag)
unsafeMemoryPtr (MemoryInstance o) = withOwned o pure

-- | Create a borrowed 'MemoryInstance' from a raw pointer (does not finalize).
borrowMemory :: Ptr MemoryInstanceTag -> IO MemoryInstance
borrowMemory p = MemoryInstance <$> mkOwned (\_ -> pure ()) p

-- | Extract the raw pointer of a 'MemoryType'.
unsafeMemoryTypePtr :: MemoryType -> IO (Ptr MemoryTypeTag)
unsafeMemoryTypePtr (MemoryType o) = withOwned o pure

-- | Create a borrowed 'MemoryType' from a raw pointer (does not finalize).
borrowMemoryType :: Ptr MemoryTypeTag -> IO MemoryType
borrowMemoryType p = MemoryType <$> mkOwned (\_ -> pure ()) p

-- | Disarm finalizer when ownership is transferred to a module instance.
disarmMemory :: MemoryInstance -> IO ()
disarmMemory (MemoryInstance o) = disarmOwned o

-- ---------------------------------------------------------------------------
-- Internal helper
-- ---------------------------------------------------------------------------

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr fp p = mkDeleter fp p

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
