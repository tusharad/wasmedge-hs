-- | Tests for WasmEdge version functions
module Test.Unit.VersionSpec (spec) where

import Test.Hspec
import Data.Char  (isDigit)
import Data.List  (isPrefixOf)
import Data.Word  (Word32)
import Foreign.C  (peekCString)
import WasmEdge.Internal.FFI.Basic

spec :: Spec
spec = describe "WasmEdge version" $ do

  it "VersionGet returns a non-empty string" $ do
    cs <- c_VersionGet
    str <- peekCString cs
    str `shouldSatisfy` (not . null)

  it "VersionGet starts with '0.'" $ do
    cs <- c_VersionGet
    str <- peekCString cs
    str `shouldSatisfy` ("0." `isPrefixOf`)

  it "VersionGetMajor returns 0 (WasmEdge 0.x)" $ do
    major <- c_VersionGetMajor
    major `shouldBe` 0

  it "VersionGetMinor returns >= 18" $ do
    minor <- c_VersionGetMinor
    minor `shouldSatisfy` (>= 18)

  it "VersionGetPatch returns a plausible patch" $ do
    patch <- c_VersionGetPatch
    patch `shouldSatisfy` (< 1000)

  it "version components are consistent with version string" $ do
    cs <- c_VersionGet
    str <- peekCString cs
    major <- c_VersionGetMajor
    minor <- c_VersionGetMinor
    patch <- c_VersionGetPatch
    let expected = show major ++ "." ++ show minor ++ "." ++ show patch
    str `shouldBe` expected
