-- | Hedgehog property tests for WasmVal encoding
module Test.Property.ValueProp (spec) where

import Test.Hspec
import Test.Hspec.Hedgehog
import Hedgehog
import qualified Hedgehog.Gen   as Gen
import qualified Hedgehog.Range as Range
import Data.Int (Int32, Int64)

import WasmEdge.Types
import WasmEdge.Value

spec :: Spec
spec = describe "WasmVal property tests" $ do

  it "I32 roundtrip: encode >> decode == id" $ hedgehog prop_i32_roundtrip
  it "I64 roundtrip: encode >> decode == id" $ hedgehog prop_i64_roundtrip
  it "F64 roundtrip: encode >> decode == id" $ hedgehog prop_f64_roundtrip

-- ---------------------------------------------------------------------------
-- Generators
-- ---------------------------------------------------------------------------

genI32 :: Gen Int32
genI32 = Gen.int32 Range.constantBounded

genI64 :: Gen Int64
genI64 = Gen.int64 Range.constantBounded

genF64 :: Gen Double
genF64 = Gen.double (Range.constant (-1e15) 1e15)

-- ---------------------------------------------------------------------------
-- Properties
-- ---------------------------------------------------------------------------

prop_i32_roundtrip :: Property
prop_i32_roundtrip = property $ do
  v <- forAll genI32
  result <- evalIO $ encodeVal (WasmI32 v) decodeVal
  result === WasmI32 v

prop_i64_roundtrip :: Property
prop_i64_roundtrip = property $ do
  v <- forAll genI64
  result <- evalIO $ encodeVal (WasmI64 v) decodeVal
  result === WasmI64 v

prop_f64_roundtrip :: Property
prop_f64_roundtrip = property $ do
  v <- forAll genF64
  result <- evalIO $ encodeVal (WasmF64 v) decodeVal
  case result of
    WasmF64 v' -> v' === v
    other      -> footnote ("unexpected: " ++ show other) >> failure
