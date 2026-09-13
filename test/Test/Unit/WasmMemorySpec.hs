{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{- |
Module      : Test.Unit.WasmMemorySpec
Description : Unit tests for the WasmMemory codec
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT

Tests round-trip encode/decode for all WasmMemory instances through
an actual Wasm linear memory instance.
-}
module Test.Unit.WasmMemorySpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Int (Int16, Int32, Int64, Int8)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word16, Word32, Word64, Word8)
import Test.Hspec

import WasmEdge.Memory
  ( MemoryInstance
  , createMemory
  , createMemoryType
  , deleteMemory
  )
import WasmEdge.Memory.Codec
import WasmEdge.Types (Limit (..))

-- | Create a fresh 1-page (64 KiB) memory for testing.
withTestMemory :: (MemoryInstance -> IO a) -> IO a
withTestMemory action = do
  mt <- createMemoryType (Limit 1 (Just 10) False)
  mem <- createMemory mt
  result <- action mem
  deleteMemory mem
  pure result

-- | Assert a round-trip: poke at offset 0, peek back, compare.
roundTrip ::
  (WasmMemory a, Show a, Eq a) =>
  MemoryInstance ->
  a ->
  Word32 -> -- read-back length
  IO ()
roundTrip mem val readLen = do
  pr <- wasmPoke mem 0 val
  pr `shouldSatisfy` \case Right _ -> True; Left _ -> False
  pk <- wasmPeek mem 0 readLen
  pk `shouldBe` Right val

spec :: Spec
spec = describe "WasmMemory codec" $ do
  around ($ ()) $ do
    it "Word8 round-trip" $ do
      withTestMemory $ \mem -> do
        roundTrip mem (42 :: Word8) 1
        roundTrip mem (0 :: Word8) 1
        roundTrip mem (255 :: Word8) 1

    it "Int8 round-trip" $ do
      withTestMemory $ \mem -> do
        roundTrip mem (0 :: Int8) 1
        roundTrip mem (127 :: Int8) 1
        roundTrip mem (-128 :: Int8) 1

    it "Word16 round-trip" $ do
      withTestMemory $ \mem -> do
        roundTrip mem (0 :: Word16) 2
        roundTrip mem (0xBEEF :: Word16) 2
        roundTrip mem (65535 :: Word16) 2

    it "Int16 round-trip" $ do
      withTestMemory $ \mem -> do
        roundTrip mem (0 :: Int16) 2
        roundTrip mem (-1 :: Int16) 2
        roundTrip mem (32767 :: Int16) 2

    it "Word32 round-trip" $ do
      withTestMemory $ \mem -> do
        roundTrip mem (0 :: Word32) 4
        roundTrip mem (0xDEADBEEF :: Word32) 4
        roundTrip mem (maxBound :: Word32) 4

    it "Int32 round-trip" $ do
      withTestMemory $ \mem -> do
        roundTrip mem (0 :: Int32) 4
        roundTrip mem (-1 :: Int32) 4
        roundTrip mem (minBound :: Int32) 4
        roundTrip mem (maxBound :: Int32) 4

    it "Word64 round-trip" $ do
      withTestMemory $ \mem -> do
        roundTrip mem (0 :: Word64) 8
        roundTrip mem (0xDEADBEEFCAFEBABE :: Word64) 8
        roundTrip mem (maxBound :: Word64) 8

    it "Int64 round-trip" $ do
      withTestMemory $ \mem -> do
        roundTrip mem (0 :: Int64) 8
        roundTrip mem (-1 :: Int64) 8
        roundTrip mem (minBound :: Int64) 8
        roundTrip mem (maxBound :: Int64) 8

    it "Float round-trip (exact bit pattern)" $ do
      withTestMemory $ \mem -> do
        roundTrip mem (0.0 :: Float) 4
        roundTrip mem (1.0 :: Float) 4
        roundTrip mem (-3.14 :: Float) 4
        roundTrip mem (1.0e10 :: Float) 4

    it "Double round-trip (exact bit pattern)" $ do
      withTestMemory $ \mem -> do
        roundTrip mem (0.0 :: Double) 8
        roundTrip mem (1.0 :: Double) 8
        roundTrip mem (-3.141592653589793 :: Double) 8

    it "Bool round-trip" $ do
      withTestMemory $ \mem -> do
        roundTrip mem True 1
        roundTrip mem False 1

    it "ByteString round-trip" $ do
      withTestMemory $ \mem -> do
        let bs = BS.pack [1, 2, 3, 4, 5]
        pr <- wasmPoke mem 0 bs
        pr `shouldBe` Right 5
        pk <- wasmPeek @ByteString mem 0 5
        pk `shouldBe` Right bs

    it "Text round-trip (UTF-8)" $ do
      withTestMemory $ \mem -> do
        let txt = "Hello, Haskell + Wasm! 🦀" :: Text
        pr <- wasmPoke mem 0 txt
        case pr of
          Left err -> expectationFailure (show err)
          Right n -> do
            pk <- wasmPeek @Text mem 0 n
            pk `shouldBe` Right txt

    it "empty ByteString round-trip" $ do
      withTestMemory $ \mem -> do
        -- WasmEdge setMemoryData with 0 bytes returns an error, so
        -- wasmPoke of an empty ByteString correctly returns Right 0 without
        -- calling setMemoryData at all.
        pr <- wasmPoke mem 0 (BS.empty :: ByteString)
        pr `shouldBe` Right 0
    -- No read-back needed for empty; just verify poke succeeded.

    it "empty Text round-trip" $ do
      withTestMemory $ \mem -> do
        pr <- wasmPoke mem 0 (T.empty :: Text)
        pr `shouldBe` Right 0

    it "(Word32, Word32) pair round-trip" $ do
      withTestMemory $ \mem -> do
        let pair = (0xDEADBEEF :: Word32, 0xCAFEBABE :: Word32)
        pr <- wasmPoke mem 0 pair
        pr `shouldBe` Right 8
        pk <- wasmPeek @(Word32, Word32) mem 0 8
        pk `shouldBe` Right pair

    it "(Int32, Int64) pair round-trip" $ do
      withTestMemory $ \mem -> do
        let pair = (-42 :: Int32, 1234567890123 :: Int64)
        pr <- wasmPoke mem 0 pair
        pr `shouldBe` Right 12
        pk <- wasmPeek @(Int32, Int64) mem 0 12
        pk `shouldBe` Right pair

    it "JSON helpers: round-trip via jsonWasmPoke/Peek" $ do
      withTestMemory $ \mem -> do
        -- Use a simple JSON-able value: a list of Int32
        -- (We can't use a custom ADT here without adding aeson instances,
        -- so we test via jsonWasmPoke/Peek directly with [Int])
        let val = [1 :: Int, 2, 3, 100, -5]
        pr <- jsonWasmPoke mem 0 val
        case pr of
          Left err -> expectationFailure (show err)
          Right n -> do
            pk <- jsonWasmPeek @[Int] mem 0 n
            pk `shouldBe` Right val

    it "multiple pokes at non-zero offsets" $ do
      withTestMemory $ \mem -> do
        _ <- wasmPoke mem 0 (0xABCD1234 :: Word32)
        _ <- wasmPoke mem 4 (0x56789012 :: Word32)
        pk1 <- wasmPeek @Word32 mem 0 4
        pk2 <- wasmPeek @Word32 mem 4 4
        pk1 `shouldBe` Right 0xABCD1234
        pk2 `shouldBe` Right 0x56789012

    it "wasmPoke does not corrupt adjacent memory" $ do
      withTestMemory $ \mem -> do
        -- Write sentinel values
        _ <- wasmPoke mem 0 (0xAAAAAAAA :: Word32)
        _ <- wasmPoke mem 8 (0xBBBBBBBB :: Word32)
        -- Overwrite middle
        _ <- wasmPoke mem 4 (0xCCCCCCCC :: Word32)
        pk0 <- wasmPeek @Word32 mem 0 4
        pk4 <- wasmPeek @Word32 mem 4 4
        pk8 <- wasmPeek @Word32 mem 8 4
        pk0 `shouldBe` Right 0xAAAAAAAA
        pk4 `shouldBe` Right 0xCCCCCCCC
        pk8 `shouldBe` Right 0xBBBBBBBB
