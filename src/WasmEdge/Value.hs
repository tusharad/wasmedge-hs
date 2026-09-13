{-# LANGUAGE MultiWayIf #-}

{- |
Module      : WasmEdge.Value
Description : Conversion between Haskell 'WasmVal' and WasmEdge C values
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : stable

Provides functions to encode 'WasmVal' into the C representation and
decode it back. These are used internally by 'WasmEdge.VM' and
'WasmEdge.Executor' when calling WASM functions.

Most users interact with 'WasmVal' directly and never call these functions.
-}
module WasmEdge.Value
  ( -- * Encoding / decoding
    encodeVal
  , decodeVal
  , withValArray
  , peekValArray
  , withCValueArray
  , valueSize

    -- * ValType conversion
  , encodeValType
  , withValTypeArray
  , peekValTypes
  ) where

import Control.Monad (forM, forM_)
import Data.WideWord.Int128 (Int128 (..))
import Data.Word (Word32)
import Foreign.C (CBool (..), CDouble (..), CFloat (..))
import Foreign.Marshal.Utils (copyBytes)
import Foreign.Ptr
import Foreign.Storable

import WasmEdge.Internal.FFI.Value
import WasmEdge.Internal.Storable
import WasmEdge.Types

-- ---------------------------------------------------------------------------
-- ValType encoding
-- ---------------------------------------------------------------------------

{- | Encode a 'ValType' into a stack-allocated 'CValType_' and pass it to
the given action.
-}
encodeValType :: ValType -> (Ptr CValType_ -> IO a) -> IO a
encodeValType vt action = allocaCValType $ \p -> do
  case vt of
    I32 -> c_ValTypeGenI32 p
    I64 -> c_ValTypeGenI64 p
    F32 -> c_ValTypeGenF32 p
    F64 -> c_ValTypeGenF64 p
    V128 -> c_ValTypeGenV128 p
    FuncRef -> c_ValTypeGenFuncRef p
    ExternRef -> c_ValTypeGenExternRef p
  action p

-- | Allocate a stack array of 'CValType_' from a '[ValType]'.
withValTypeArray :: [ValType] -> (Ptr CValType_ -> Word32 -> IO a) -> IO a
withValTypeArray vts action =
  withCValTypeArray (length vts) $ \arr -> do
    forM_ (zip [0 ..] vts) $ \(i, vt) ->
      encodeValType vt $ \p -> do
        -- Copy the 8-byte ValType into position i
        let dst = arr `plusPtr` (i * valTypeSize)
        copyBytes dst p valTypeSize
    action arr (fromIntegral (length vts))

-- | Decode an array of 'CValType_' from a C array.
peekValTypes :: Ptr CValType_ -> Word32 -> IO [ValType]
peekValTypes arr n =
  forM [0 .. fromIntegral n - 1] $ \i -> do
    let p = arr `plusPtr` (i * valTypeSize)
    -- Check each type in priority order
    isI32 <- c_ValTypeIsI32 p
    isI64 <- c_ValTypeIsI64 p
    isF32 <- c_ValTypeIsF32 p
    isF64 <- c_ValTypeIsF64 p
    isV128 <- c_ValTypeIsV128 p
    isFR <- c_ValTypeIsFuncRef p
    isER <- c_ValTypeIsExternRef p
    pure $
      if
        | toBool isI32 -> I32
        | toBool isI64 -> I64
        | toBool isF32 -> F32
        | toBool isF64 -> F64
        | toBool isV128 -> V128
        | toBool isFR -> FuncRef
        | toBool isER -> ExternRef
        | otherwise -> I32 -- should not happen

toBool :: CBool -> Bool
toBool (CBool 0) = False
toBool _ = True

-- ---------------------------------------------------------------------------
-- WasmVal encoding / decoding
-- ---------------------------------------------------------------------------

-- | Encode a single 'WasmVal' into a stack-allocated 'CValue_'.
encodeVal :: WasmVal -> (Ptr CValue_ -> IO a) -> IO a
encodeVal val action = allocaCValue $ \p -> do
  case val of
    WasmI32 v -> c_ValueGenI32 p v
    WasmI64 v -> c_ValueGenI64 p v
    WasmF32 v -> c_ValueGenF32 p (CFloat v)
    WasmF64 v -> c_ValueGenF64 p (CDouble v)
    WasmV128 (Int128 hi lo) -> c_ValueGenV128 p hi lo
    WasmFuncRef Nothing -> c_ValueGenNullFuncRef p
    WasmFuncRef (Just (FuncRefPtr fp)) ->
      c_ValueGenFuncRef p (castPtr fp)
    WasmExternRef Nothing -> c_ValueGenNullExternRef p
    WasmExternRef (Just (ExternRefPtr rp)) ->
      c_ValueGenExternRef p rp
  action p

-- | Decode a 'WasmVal' from a 'CValue_' pointer.
decodeVal :: Ptr CValue_ -> IO WasmVal
decodeVal p = do
  -- First determine the type
  allocaCValType $ \tp -> do
    c_ValueGetType p tp
    isI32 <- c_ValTypeIsI32 tp
    isI64 <- c_ValTypeIsI64 tp
    isF32 <- c_ValTypeIsF32 tp
    isF64 <- c_ValTypeIsF64 tp
    isV128 <- c_ValTypeIsV128 tp
    isFR <- c_ValTypeIsFuncRef tp
    isER <- c_ValTypeIsExternRef tp
    if
      | toBool isI32 -> WasmI32 <$> c_ValueGetI32 p
      | toBool isI64 -> WasmI64 <$> c_ValueGetI64 p
      | toBool isF32 -> do CFloat v <- c_ValueGetF32 p; pure (WasmF32 v)
      | toBool isF64 -> do CDouble v <- c_ValueGetF64 p; pure (WasmF64 v)
      | toBool isV128 -> do
          hiPtr <- malloc
          loPtr <- malloc
          c_ValueGetV128 p hiPtr loPtr
          hi <- peek hiPtr
          lo <- peek loPtr
          free hiPtr
          free loPtr
          pure $ WasmV128 (Int128 hi lo)
      | toBool isFR -> do
          isNull <- c_ValueIsNullRef p
          if toBool isNull
            then pure (WasmFuncRef Nothing)
            else do
              fp <- c_ValueGetFuncRef p
              pure $ WasmFuncRef (Just (FuncRefPtr (castPtr fp)))
      | toBool isER -> do
          isNull <- c_ValueIsNullRef p
          if toBool isNull
            then pure (WasmExternRef Nothing)
            else do
              rp <- c_ValueGetExternRef p
              pure $ WasmExternRef (Just (ExternRefPtr rp))
      | otherwise -> pure (WasmI32 0) -- should not happen

-- | Encode a '[WasmVal]' into a C array and pass the array to the action.
withValArray :: [WasmVal] -> (Ptr () -> Word32 -> IO a) -> IO a
withValArray [] action = action nullPtr 0
withValArray vals action =
  withCValueArray (length vals) $ \arr -> do
    forM_ (zip [0 ..] vals) $ \(i, val) ->
      encodeVal val $ \p ->
        copyBytes (arr `plusPtr` (i * valueSize)) p valueSize
    action (castPtr arr) (fromIntegral (length vals))

-- | Decode a '[WasmVal]' from a C array of 'CValue_'.
peekValArray :: Ptr () -> Word32 -> IO [WasmVal]
peekValArray arr n =
  forM [0 .. fromIntegral n - 1] $ \i ->
    decodeVal (castPtr (arr `plusPtr` (i * valueSize)))

-- Helper since GHC imports are needed
foreign import ccall unsafe "malloc" malloc :: IO (Ptr a)
foreign import ccall unsafe "free" free :: Ptr a -> IO ()
