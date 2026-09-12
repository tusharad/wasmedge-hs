-- | Hedgehog property tests for WasmEdge_String roundtrips
module Test.Property.StringProp (spec) where

import Test.Hspec
import Test.Hspec.Hedgehog
import qualified Hedgehog.Gen   as Gen
import qualified Hedgehog.Range as Range
import Data.Text (Text)
import qualified Data.Text as T

import WasmEdge.Internal.Utils  (withWasmString, peekWasmString)

spec :: Spec
spec = describe "WasmEdge_String property tests" $ do

  it "ASCII string roundtrip" $ hedgehog prop_ascii_roundtrip
  it "UTF-8 string roundtrip" $ hedgehog prop_utf8_roundtrip
  it "empty string roundtrip" $ hedgehog prop_empty_roundtrip

-- ---------------------------------------------------------------------------
-- Generators
-- ---------------------------------------------------------------------------

genAscii :: Gen Text
genAscii = T.pack <$> Gen.list (Range.linear 0 256) Gen.alpha

genUnicode :: Gen Text
genUnicode = Gen.text (Range.linear 0 128) Gen.unicode

-- ---------------------------------------------------------------------------
-- Properties
-- ---------------------------------------------------------------------------

prop_ascii_roundtrip :: PropertyT IO ()
prop_ascii_roundtrip = do
  txt <- forAll genAscii
  result <- evalIO $ withWasmString txt peekWasmString
  result === txt

prop_utf8_roundtrip :: PropertyT IO ()
prop_utf8_roundtrip = do
  txt <- forAll genUnicode
  result <- evalIO $ withWasmString txt peekWasmString
  result === txt

prop_empty_roundtrip :: PropertyT IO ()
prop_empty_roundtrip = do
  result <- evalIO $ withWasmString T.empty peekWasmString
  result === T.empty
