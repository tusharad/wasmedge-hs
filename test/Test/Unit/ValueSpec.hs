-- | Unit tests for WasmEdge value encoding/decoding roundtrips
module Test.Unit.ValueSpec (spec) where

import Data.Int (Int32, Int64)
import Foreign.C (CBool (..))
import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.Ptr
import Test.Hspec

import WasmEdge.Internal.FFI.Value
import WasmEdge.Internal.Storable (CValType_, allocaCValue)
import WasmEdge.Types
import WasmEdge.Value

spec :: Spec
spec = describe "WasmEdge value encoding" $ do
  describe "I32 roundtrip" $ do
    it "encodes and decodes 0" $ roundtripI32 0
    it "encodes and decodes maxBound" $ roundtripI32 maxBound
    it "encodes and decodes minBound" $ roundtripI32 minBound
    it "encodes and decodes 42" $ roundtripI32 42
    it "encodes and decodes -1" $ roundtripI32 (-1)

  describe "I64 roundtrip" $ do
    it "encodes and decodes 0" $ roundtripI64 0
    it "encodes and decodes maxBound" $ roundtripI64 maxBound
    it "encodes and decodes minBound" $ roundtripI64 minBound

  describe "F32 roundtrip" $ do
    it "encodes and decodes 0.0" $ roundtripF32 0.0
    it "encodes and decodes 3.14" $ roundtripF32 3.14
    it "encodes and decodes -1.5" $ roundtripF32 (-1.5)

  describe "F64 roundtrip" $ do
    it "encodes and decodes 0.0" $ roundtripF64 0.0
    it "encodes and decodes pi" $ roundtripF64 3.141592653589793
    it "encodes and decodes -1e300" $ roundtripF64 (-1e300)

  describe "null references" $ do
    it "null FuncRef roundtrip" $ do
      val <- encodeDecodeVal (WasmFuncRef Nothing)
      val `shouldBe` WasmFuncRef Nothing

    it "null ExternRef roundtrip" $ do
      val <- encodeDecodeVal (WasmExternRef Nothing)
      val `shouldBe` WasmExternRef Nothing

  describe "ValType generators" $ do
    it "ValTypeGenI32 reports IsI32" $ do
      allocaCValue $ \_ -> allocaValType $ \tp -> do
        c_ValTypeGenI32 tp
        CBool b <- c_ValTypeIsI32 tp
        b `shouldSatisfy` (/= 0)

    it "ValTypeGenF64 reports IsF64" $ do
      allocaValType $ \tp -> do
        c_ValTypeGenF64 tp
        CBool b <- c_ValTypeIsF64 tp
        b `shouldSatisfy` (/= 0)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

allocaValType :: (Ptr CValType_ -> IO a) -> IO a
allocaValType = allocaBytes 8

roundtripI32 :: Int32 -> IO ()
roundtripI32 v = do
  val <- encodeDecodeVal (WasmI32 v)
  val `shouldBe` WasmI32 v

roundtripI64 :: Int64 -> IO ()
roundtripI64 v = do
  val <- encodeDecodeVal (WasmI64 v)
  val `shouldBe` WasmI64 v

roundtripF32 :: Float -> IO ()
roundtripF32 v = do
  val <- encodeDecodeVal (WasmF32 v)
  case val of
    WasmF32 v' -> v' `shouldBe` v
    _ -> expectationFailure "Expected WasmF32"

roundtripF64 :: Double -> IO ()
roundtripF64 v = do
  val <- encodeDecodeVal (WasmF64 v)
  case val of
    WasmF64 v' -> v' `shouldBe` v
    _ -> expectationFailure "Expected WasmF64"

encodeDecodeVal :: WasmVal -> IO WasmVal
encodeDecodeVal val = encodeVal val decodeVal
