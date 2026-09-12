-- |
-- Module      : WasmEdge.Table
-- Description : WasmEdge table contexts
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : stable
--
-- Provides types and functions for WebAssembly table instances and types:
--
-- * 'TableType' — describes reference type and element limits
-- * 'TableInstance' — a runtime table instance
module WasmEdge.Table
  ( -- * Table type
    TableType
  , createTableType
  , deleteTableType
  , withTableType
  , getTableTypeRefType
  , getTableTypeLimit

    -- * Table instance
  , TableInstance
  , createTable
  , deleteTable
  , withTable
  , getTableType
  , getTableData
  , setTableData
  , getTableSize
  , growTable

    -- * Internal / borrowed pointers
  , unsafeTablePtr
  , borrowTable
  , unsafeTableTypePtr
  , borrowTableType
  , disarmTable
  ) where

import Control.Exception     (bracket, throwIO)
import Foreign.C             (CBool (..))
import Foreign.Marshal.Alloc (alloca)
import Foreign.Ptr           (Ptr, FunPtr, nullPtr)
import Foreign.Storable      (peek)
import Data.Word             (Word32)

import WasmEdge.Types
import WasmEdge.Error
import WasmEdge.Value        (encodeVal, decodeVal, encodeValType, peekValTypes)
import WasmEdge.Internal.Types     (TableTypeTag, TableInstanceTag)
import WasmEdge.Internal.Ownership (OwnedCtx, mkOwned, withOwned, finalizeOwned, disarmOwned)
import WasmEdge.Internal.Storable  (allocaCValType, allocaCValue, allocaCResult)
import WasmEdge.Internal.Utils     (checkResult)
import WasmEdge.Internal.FFI.Instance

-- ---------------------------------------------------------------------------
-- TableType
-- ---------------------------------------------------------------------------

-- | A WebAssembly table type, specifying the reference type (FuncRef or ExternRef)
-- and element limits.
newtype TableType = TableType (OwnedCtx TableTypeTag)

-- | Create a 'TableType' with the given element reference type and 'Limit'.
createTableType :: ValType -> Limit -> IO TableType
createTableType refType lim =
  encodeValType refType $ \vtPtr -> do
    let hasMax  = CBool (case limitMax lim of Just _ -> 1; Nothing -> 0)
        minVal  = fromIntegral (limitMin lim)
        maxVal  = case limitMax lim of Just m -> fromIntegral m; Nothing -> 0
        shared  = CBool (if limitShared lim then 1 else 0)
        is64    = CBool 0
    p <- c_TableTypeCreate vtPtr hasMax minVal maxVal shared is64
    if p == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_TableTypeCreate returned NULL"
      else TableType <$> mkOwned (appFunPtr c_TableTypeDelete) p

-- | Delete a 'TableType'.
deleteTableType :: TableType -> IO ()
deleteTableType (TableType o) = finalizeOwned o

-- | Scoped 'TableType'.
withTableType :: ValType -> Limit -> (TableType -> IO a) -> IO a
withTableType vt lim = bracket (createTableType vt lim) deleteTableType

-- | Get the reference type of a 'TableType'.
getTableTypeRefType :: TableType -> IO ValType
getTableTypeRefType (TableType o) =
  withOwned o $ \p ->
  allocaCValType $ \vtPtr -> do
    c_TableTypeGetRefType p vtPtr
    types <- peekValTypes vtPtr 1
    case types of
      (t:_) -> pure t
      []    -> pure FuncRef

-- | Get the 'Limit' of a 'TableType'.
getTableTypeLimit :: TableType -> IO Limit
getTableTypeLimit (TableType o) =
  withOwned o $ \p -> do
    limPtr <- c_TableTypeGetLimit p
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
-- TableInstance
-- ---------------------------------------------------------------------------

-- | A runtime WebAssembly table instance.
newtype TableInstance = TableInstance (OwnedCtx TableInstanceTag)

-- | Create a 'TableInstance' from a 'TableType'.
createTable :: TableType -> IO TableInstance
createTable (TableType ttOwned) =
  withOwned ttOwned $ \ttPtr -> do
    p <- c_TableInstanceCreate ttPtr
    if p == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_TableInstanceCreate returned NULL"
      else TableInstance <$> mkOwned (appFunPtr c_TableInstanceDelete) p

-- | Delete a 'TableInstance'.
deleteTable :: TableInstance -> IO ()
deleteTable (TableInstance o) = finalizeOwned o

-- | Scoped 'TableInstance'.
withTable :: TableType -> (TableInstance -> IO a) -> IO a
withTable tt = bracket (createTable tt) deleteTable

-- | Get the 'TableType' of a 'TableInstance'.
getTableType :: TableInstance -> IO TableType
getTableType (TableInstance o) =
  withOwned o $ \p -> do
    tp <- c_TableInstanceGetTableType p
    if tp == nullPtr
      then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_TableInstanceGetTableType returned NULL"
      else borrowTableType tp

-- | Get the reference value at an offset in the table.
getTableData :: TableInstance -> Word32 -> IO (WasmResult WasmVal)
getTableData (TableInstance o) offset =
  withOwned o $ \p ->
  allocaCValue $ \valPtr ->
  allocaCResult $ \resPtr -> do
    c_TableInstanceGetData resPtr p valPtr offset
    res <- checkResult resPtr
    case res of
      Left err -> pure (Left err)
      Right () -> Right <$> decodeVal valPtr

-- | Set the reference value at an offset in the table.
setTableData :: TableInstance -> Word32 -> WasmVal -> IO (WasmResult ())
setTableData (TableInstance o) offset val =
  withOwned o $ \p ->
  encodeVal val $ \valPtr ->
  allocaCResult $ \resPtr -> do
    c_TableInstanceSetData resPtr p valPtr offset
    checkResult resPtr

-- | Get the current element count of a table.
getTableSize :: TableInstance -> IO Word32
getTableSize (TableInstance o) =
  withOwned o c_TableInstanceGetSize

-- | Grow the table by @count@ elements.
growTable :: TableInstance -> Word32 -> IO (WasmResult ())
growTable (TableInstance o) count =
  withOwned o $ \p ->
  allocaCResult $ \resPtr -> do
    c_TableInstanceGrow resPtr p count
    checkResult resPtr

-- ---------------------------------------------------------------------------
-- Unsafe / internal pointer helpers
-- ---------------------------------------------------------------------------

-- | Extract the raw pointer of a 'TableInstance'.
unsafeTablePtr :: TableInstance -> IO (Ptr TableInstanceTag)
unsafeTablePtr (TableInstance o) = withOwned o pure

-- | Create a borrowed 'TableInstance' from a raw pointer (does not finalize).
borrowTable :: Ptr TableInstanceTag -> IO TableInstance
borrowTable p = TableInstance <$> mkOwned (\_ -> pure ()) p

-- | Extract the raw pointer of a 'TableType'.
unsafeTableTypePtr :: TableType -> IO (Ptr TableTypeTag)
unsafeTableTypePtr (TableType o) = withOwned o pure

-- | Create a borrowed 'TableType' from a raw pointer (does not finalize).
borrowTableType :: Ptr TableTypeTag -> IO TableType
borrowTableType p = TableType <$> mkOwned (\_ -> pure ()) p

-- | Disarm finalizer when ownership is transferred to a module instance.
disarmTable :: TableInstance -> IO ()
disarmTable (TableInstance o) = disarmOwned o

-- ---------------------------------------------------------------------------
-- Internal helper
-- ---------------------------------------------------------------------------

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr fp p = mkDeleter fp p

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
