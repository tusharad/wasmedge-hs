{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : WasmEdge.Memory.Codec
Description : Typeclass for serialising Haskell values through Wasm linear memory
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

WebAssembly's type system only has four numeric types and references.
Every complex value — @Text@, @ByteString@, a list, or any ADT — must be
transported through __linear memory__: the Wasm module's heap.

The canonical pattern (used by the Rust and Go SDKs) is:

  1. The guest (Wasm) module exports @alloc(size: i32) -> i32@ and
     @dealloc(ptr: i32, len: i32)@.
  2. The host passes a @(ptr: i32, len: i32)@ pair for every buffer argument.
  3. Both sides serialise complex data to\/from a flat byte representation.

'WasmMemory' standardises step 3 on the Haskell side.

== Encoding conventions

* Primitive numeric types use __little-endian__ binary encoding (matches Wasm's
  native byte order).
* 'Text' is encoded as __UTF-8__ bytes.
* 'ByteString' is passed __as-is__ (zero-copy where possible).
* Complex ADTs should implement 'WasmMemory' using 'jsonWasmPoke' \/ 'jsonWasmPeek',
  which serialises via @aeson@ JSON — the same convention used by @wit-bindgen@
  and the WASI ecosystem.

== Typical usage

@
-- Host reads a Text value from a Wasm linear memory buffer:
txt \<- wasmPeek \@Text mem offset len

-- Host writes an ADT back into linear memory (assuming a JSON instance):
Right n \<- wasmPoke mem retOffset myRecord
@

See 'WasmEdge.Memory.Alloc' for the high-level bracket that combines
allocation, marshalling, and function invocation in one call.
-}
module WasmEdge.Memory.Codec
  ( -- * Core typeclass
    WasmMemory (..)

    -- * Fixed-size subclass
  , FixedWasmMemory (..)
  , fixedPoke
  , fixedPeek

    -- * JSON codec helpers (for custom ADTs)
  , jsonWasmPoke
  , jsonWasmPeek
  , WasmJSON (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Aeson qualified as Aeson
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Int (Int16, Int32, Int64, Int8)
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word16, Word32, Word64, Word8)
import GHC.Float (castDoubleToWord64, castFloatToWord32, castWord32ToFloat, castWord64ToDouble)

import WasmEdge.Error (ErrCategory (..), WasmEdgeError (..), WasmResult)
import WasmEdge.Memory (MemoryInstance, getMemoryData, setMemoryData)

-- ---------------------------------------------------------------------------
-- Core typeclass
-- ---------------------------------------------------------------------------

{- | A type that can be serialised to and deserialised from a contiguous slice
of WebAssembly linear memory.

Minimal complete definition: 'wasmPeek' + 'wasmPoke'.

For fixed-size types (primitives, fixed-size tuples), implement
'FixedWasmMemory' and use 'fixedPeek' \/ 'fixedPoke' as the default methods.

For JSON-serialisable ADTs use 'jsonWasmPeek' \/ 'jsonWasmPoke'.
-}
class WasmMemory a where
  {- | Read a value of type @a@ from @len@ bytes of linear memory at @offset@.
  Returns 'Left' on out-of-bounds access or deserialisation failure.
  -}
  wasmPeek ::
    -- | The linear memory instance
    MemoryInstance ->
    -- | Byte offset in linear memory
    Word32 ->
    -- | Byte length of the slice
    Word32 ->
    IO (WasmResult a)

  {- | Write a value of type @a@ into linear memory at @offset@.
  Returns @Right n@ where @n@ is the number of bytes written, or 'Left' on
  out-of-bounds access.
  -}
  wasmPoke ::
    -- | The linear memory instance
    MemoryInstance ->
    -- | Byte offset to write at
    Word32 ->
    -- | The value to serialise
    a ->
    -- | @Right@ bytes written, or @Left@ error
    IO (WasmResult Word32)

-- ---------------------------------------------------------------------------
-- Fixed-size subclass
-- ---------------------------------------------------------------------------

{- | A 'WasmMemory' type with a statically-known byte width.
Implement this for all primitive types.
-}
class WasmMemory a => FixedWasmMemory a where
  -- | Byte width of the serialised form.
  wasmWidth :: Proxy a -> Word32

  -- | Serialise to exactly 'wasmWidth' bytes.
  serialise :: a -> ByteString

  -- | Deserialise from at least 'wasmWidth' bytes.
  deserialise :: ByteString -> Either String a

-- | Default 'wasmPoke' for any 'FixedWasmMemory' instance.
fixedPoke :: (FixedWasmMemory a) => MemoryInstance -> Word32 -> a -> IO (WasmResult Word32)
fixedPoke mem offset val = do
  let bs = serialise val
  res <- setMemoryData mem offset bs
  pure (fmap (const (fromIntegral (BS.length bs))) res)

-- | Default 'wasmPeek' for any 'FixedWasmMemory' instance.
fixedPeek ::
  forall a.
  (FixedWasmMemory a) =>
  MemoryInstance ->
  Word32 ->
  Word32 ->
  IO (WasmResult a)
fixedPeek mem offset _len = do
  let w = wasmWidth (Proxy @a)
  res <- getMemoryData mem offset w
  pure $
    res >>= \bs ->
      case deserialise bs of
        Left msg ->
          Left
            ( WasmEdgeError
                ErrCategory_UserDefined
                10
                (TE.decodeUtf8Lenient (BS.pack (map (fromIntegral . fromEnum) msg)))
            )
        Right v -> Right v

-- ---------------------------------------------------------------------------
-- JSON codec helpers
-- ---------------------------------------------------------------------------

{- | Write any 'ToJSON' value into linear memory as a UTF-8 JSON blob.
Returns the number of bytes written.
-}
jsonWasmPoke :: (ToJSON a) => MemoryInstance -> Word32 -> a -> IO (WasmResult Word32)
jsonWasmPoke mem offset val = do
  let bs = BL.toStrict (Aeson.encode val)
  res <- setMemoryData mem offset bs
  pure (fmap (const (fromIntegral (BS.length bs))) res)

{- | Read a UTF-8 JSON blob from linear memory and decode it as a 'FromJSON'
value.
-}
jsonWasmPeek :: (FromJSON a) => MemoryInstance -> Word32 -> Word32 -> IO (WasmResult a)
jsonWasmPeek mem offset len = do
  res <- getMemoryData mem offset len
  pure $
    res >>= \bs ->
      case Aeson.eitherDecodeStrict bs of
        Left msg ->
          Left
            ( WasmEdgeError
                ErrCategory_UserDefined
                11
                (TE.decodeUtf8Lenient (BS.pack (map (fromIntegral . fromEnum) msg)))
            )
        Right v -> Right v

{- | Newtype wrapper to derive 'WasmMemory' for any type with 'ToJSON' and 'FromJSON' via @DerivingVia@.

@
data Person = Person { name :: Text, age :: Int }
  deriving stock (Generic, Show, Eq)
  deriving anyclass (ToJSON, FromJSON)
  deriving (WasmMemory) via (WasmJSON Person)
@
-}
newtype WasmJSON a = WasmJSON {unWasmJSON :: a}
  deriving stock (Eq, Show)
  deriving newtype (ToJSON, FromJSON)

instance (ToJSON a, FromJSON a) => WasmMemory (WasmJSON a) where
  wasmPoke mem offset (WasmJSON val) = jsonWasmPoke mem offset val
  wasmPeek mem offset len = fmap WasmJSON <$> jsonWasmPeek mem offset len

-- ---------------------------------------------------------------------------
-- Utility: little-endian encode / decode helpers
-- ---------------------------------------------------------------------------

leWord16 :: Word16 -> ByteString
leWord16 w =
  BS.pack
    [ fromIntegral (w .&. 0xFF)
    , fromIntegral ((w `shiftR` 8) .&. 0xFF)
    ]

leWord32 :: Word32 -> ByteString
leWord32 w =
  BS.pack
    [ fromIntegral (w .&. 0xFF)
    , fromIntegral ((w `shiftR` 8) .&. 0xFF)
    , fromIntegral ((w `shiftR` 16) .&. 0xFF)
    , fromIntegral ((w `shiftR` 24) .&. 0xFF)
    ]

leWord64 :: Word64 -> ByteString
leWord64 w =
  BS.pack
    [ fromIntegral (w .&. 0xFF)
    , fromIntegral ((w `shiftR` 8) .&. 0xFF)
    , fromIntegral ((w `shiftR` 16) .&. 0xFF)
    , fromIntegral ((w `shiftR` 24) .&. 0xFF)
    , fromIntegral ((w `shiftR` 32) .&. 0xFF)
    , fromIntegral ((w `shiftR` 40) .&. 0xFF)
    , fromIntegral ((w `shiftR` 48) .&. 0xFF)
    , fromIntegral ((w `shiftR` 56) .&. 0xFF)
    ]

fromLeWord16 :: ByteString -> Word16
fromLeWord16 bs
  | BS.length bs < 2 = 0
  | otherwise =
      fromIntegral (BS.index bs 0)
        .|. (fromIntegral (BS.index bs 1) `shiftL` 8)

fromLeWord32 :: ByteString -> Word32
fromLeWord32 bs
  | BS.length bs < 4 = 0
  | otherwise =
      fromIntegral (BS.index bs 0)
        .|. (fromIntegral (BS.index bs 1) `shiftL` 8)
        .|. (fromIntegral (BS.index bs 2) `shiftL` 16)
        .|. (fromIntegral (BS.index bs 3) `shiftL` 24)

fromLeWord64 :: ByteString -> Word64
fromLeWord64 bs
  | BS.length bs < 8 = 0
  | otherwise =
      fromIntegral (BS.index bs 0)
        .|. (fromIntegral (BS.index bs 1) `shiftL` 8)
        .|. (fromIntegral (BS.index bs 2) `shiftL` 16)
        .|. (fromIntegral (BS.index bs 3) `shiftL` 24)
        .|. (fromIntegral (BS.index bs 4) `shiftL` 32)
        .|. (fromIntegral (BS.index bs 5) `shiftL` 40)
        .|. (fromIntegral (BS.index bs 6) `shiftL` 48)
        .|. (fromIntegral (BS.index bs 7) `shiftL` 56)

-- ---------------------------------------------------------------------------
-- Primitive instances
-- ---------------------------------------------------------------------------

-- | 'Word8' — 1 byte, identity encoding.
instance WasmMemory Word8 where
  wasmPeek mem offset _ = fmap (fmap BS.head) (getMemoryData mem offset 1)
  wasmPoke mem offset v = fmap (fmap (const 1)) (setMemoryData mem offset (BS.singleton v))

instance FixedWasmMemory Word8 where
  wasmWidth _ = 1
  serialise = BS.singleton
  deserialise bs
    | BS.null bs = Left "WasmMemory Word8: empty buffer"
    | otherwise = Right (BS.head bs)

-- | 'Int8' — 1 byte, two's complement.
instance WasmMemory Int8 where
  wasmPeek mem offset len = fmap (fmap (fromIntegral . BS.head)) (getMemoryData mem offset (max 1 len))
  wasmPoke mem offset v = fmap (fmap (const 1)) (setMemoryData mem offset (BS.singleton (fromIntegral v)))

instance FixedWasmMemory Int8 where
  wasmWidth _ = 1
  serialise = BS.singleton . fromIntegral
  deserialise bs
    | BS.null bs = Left "WasmMemory Int8: empty buffer"
    | otherwise = Right (fromIntegral (BS.head bs))

-- | 'Word16' — 2 bytes, little-endian.
instance WasmMemory Word16 where
  wasmPeek mem offset _ = fmap (fmap fromLeWord16) (getMemoryData mem offset 2)
  wasmPoke mem offset v = fmap (fmap (const 2)) (setMemoryData mem offset (leWord16 v))

instance FixedWasmMemory Word16 where
  wasmWidth _ = 2
  serialise = leWord16
  deserialise bs
    | BS.length bs < 2 = Left "WasmMemory Word16: buffer too short"
    | otherwise = Right (fromLeWord16 bs)

-- | 'Int16' — 2 bytes, little-endian two's complement.
instance WasmMemory Int16 where
  wasmPeek mem offset _ = fmap (fmap (fromIntegral . fromLeWord16)) (getMemoryData mem offset 2)
  wasmPoke mem offset v = fmap (fmap (const 2)) (setMemoryData mem offset (leWord16 (fromIntegral v)))

instance FixedWasmMemory Int16 where
  wasmWidth _ = 2
  serialise = leWord16 . fromIntegral
  deserialise bs
    | BS.length bs < 2 = Left "WasmMemory Int16: buffer too short"
    | otherwise = Right (fromIntegral (fromLeWord16 bs))

-- | 'Word32' — 4 bytes, little-endian.
instance WasmMemory Word32 where
  wasmPeek mem offset _ = fmap (fmap fromLeWord32) (getMemoryData mem offset 4)
  wasmPoke mem offset v = fmap (fmap (const 4)) (setMemoryData mem offset (leWord32 v))

instance FixedWasmMemory Word32 where
  wasmWidth _ = 4
  serialise = leWord32
  deserialise bs
    | BS.length bs < 4 = Left "WasmMemory Word32: buffer too short"
    | otherwise = Right (fromLeWord32 bs)

-- | 'Int32' — 4 bytes, little-endian two's complement.
instance WasmMemory Int32 where
  wasmPeek mem offset _ = fmap (fmap (fromIntegral . fromLeWord32)) (getMemoryData mem offset 4)
  wasmPoke mem offset v = fmap (fmap (const 4)) (setMemoryData mem offset (leWord32 (fromIntegral v)))

instance FixedWasmMemory Int32 where
  wasmWidth _ = 4
  serialise = leWord32 . fromIntegral
  deserialise bs
    | BS.length bs < 4 = Left "WasmMemory Int32: buffer too short"
    | otherwise = Right (fromIntegral (fromLeWord32 bs))

-- | 'Word64' — 8 bytes, little-endian.
instance WasmMemory Word64 where
  wasmPeek mem offset _ = fmap (fmap fromLeWord64) (getMemoryData mem offset 8)
  wasmPoke mem offset v = fmap (fmap (const 8)) (setMemoryData mem offset (leWord64 v))

instance FixedWasmMemory Word64 where
  wasmWidth _ = 8
  serialise = leWord64
  deserialise bs
    | BS.length bs < 8 = Left "WasmMemory Word64: buffer too short"
    | otherwise = Right (fromLeWord64 bs)

-- | 'Int64' — 8 bytes, little-endian two's complement.
instance WasmMemory Int64 where
  wasmPeek mem offset _ = fmap (fmap (fromIntegral . fromLeWord64)) (getMemoryData mem offset 8)
  wasmPoke mem offset v = fmap (fmap (const 8)) (setMemoryData mem offset (leWord64 (fromIntegral v)))

instance FixedWasmMemory Int64 where
  wasmWidth _ = 8
  serialise = leWord64 . fromIntegral
  deserialise bs
    | BS.length bs < 8 = Left "WasmMemory Int64: buffer too short"
    | otherwise = Right (fromIntegral (fromLeWord64 bs))

-- | 'Float' — 4 bytes, IEEE 754 single-precision little-endian.
instance WasmMemory Float where
  wasmPeek mem offset _ =
    fmap (fmap (castWord32ToFloat . fromLeWord32)) (getMemoryData mem offset 4)
  wasmPoke mem offset v =
    fmap (fmap (const 4)) (setMemoryData mem offset (leWord32 (castFloatToWord32 v)))

instance FixedWasmMemory Float where
  wasmWidth _ = 4
  serialise = leWord32 . castFloatToWord32
  deserialise bs
    | BS.length bs < 4 = Left "WasmMemory Float: buffer too short"
    | otherwise = Right (castWord32ToFloat (fromLeWord32 bs))

-- | 'Double' — 8 bytes, IEEE 754 double-precision little-endian.
instance WasmMemory Double where
  wasmPeek mem offset _ =
    fmap (fmap (castWord64ToDouble . fromLeWord64)) (getMemoryData mem offset 8)
  wasmPoke mem offset v =
    fmap (fmap (const 8)) (setMemoryData mem offset (leWord64 (castDoubleToWord64 v)))

instance FixedWasmMemory Double where
  wasmWidth _ = 8
  serialise = leWord64 . castDoubleToWord64
  deserialise bs
    | BS.length bs < 8 = Left "WasmMemory Double: buffer too short"
    | otherwise = Right (castWord64ToDouble (fromLeWord64 bs))

-- | 'Bool' — 1 byte: 0 = 'False', 1 = 'True'.
instance WasmMemory Bool where
  wasmPeek mem offset len = fmap (fmap (/= 0)) (wasmPeek @Word8 mem offset len)
  wasmPoke mem offset v = wasmPoke mem offset (if v then 1 :: Word8 else 0)

instance FixedWasmMemory Bool where
  wasmWidth _ = 1
  serialise False = BS.singleton 0
  serialise True = BS.singleton 1
  deserialise bs
    | BS.null bs = Left "WasmMemory Bool: empty buffer"
    | otherwise = Right (BS.head bs /= 0)

-- ---------------------------------------------------------------------------
-- Variable-length instances
-- ---------------------------------------------------------------------------

{- | 'ByteString' — raw bytes, zero-copy.

The entire slice @[offset .. offset+len)@ is returned\/written as-is.
Writing an empty 'ByteString' is a no-op (returns @Right 0@).
-}
instance WasmMemory ByteString where
  wasmPeek = getMemoryData
  wasmPoke _mem _offset bs
    | BS.null bs = pure (Right 0)
  wasmPoke mem offset bs = do
    res <- setMemoryData mem offset bs
    pure (fmap (const (fromIntegral (BS.length bs))) res)

{- | 'Text' — UTF-8 encoded bytes.

The codec is strict UTF-8: an invalid byte sequence returns @Left@ with a
'WasmEdgeError' rather than silently replacing bytes with the replacement
character. Use 'WasmMemory ByteString' if you need raw bytes.
Writing empty 'Text' is a no-op (returns @Right 0@).
-}
instance WasmMemory Text where
  wasmPeek mem offset len = do
    res <- getMemoryData mem offset len
    pure $
      res >>= \bs ->
        case TE.decodeUtf8' bs of
          Left unicodeEx ->
            Left
              ( WasmEdgeError
                  ErrCategory_UserDefined
                  12
                  ("WasmMemory Text: invalid UTF-8 in guest memory: " <> T.pack (show unicodeEx))
              )
          Right txt -> Right txt
  wasmPoke _mem _offset t
    | T.null t = pure (Right 0)
  wasmPoke mem offset t = do
    let bs = TE.encodeUtf8 t
    res <- setMemoryData mem offset bs
    pure (fmap (const (fromIntegral (BS.length bs))) res)

-- | @['Word8']@ — raw bytes (wraps via 'ByteString').
instance WasmMemory [Word8] where
  wasmPeek mem offset len = fmap (fmap BS.unpack) (getMemoryData mem offset len)
  wasmPoke mem offset ws = wasmPoke mem offset (BS.pack ws)

-- ---------------------------------------------------------------------------
-- Pair of fixed-size values
-- ---------------------------------------------------------------------------

{- | A pair of fixed-size values is stored sequentially: @a@ at @offset@,
@b@ at @offset + wasmWidth \@a@.
-}
instance (FixedWasmMemory a, FixedWasmMemory b) => WasmMemory (a, b) where
  wasmPeek mem offset _ = do
    let wa = wasmWidth (Proxy @a)
        wb = wasmWidth (Proxy @b)
    ra <- wasmPeek mem offset wa
    rb <- wasmPeek mem (offset + wa) wb
    pure $ (,) <$> ra <*> rb

  wasmPoke mem offset (a, b) = do
    let wa = wasmWidth (Proxy @a)
    ra <- wasmPoke mem offset a
    rb <- wasmPoke mem (offset + wa) b
    pure $ (+) <$> ra <*> rb
