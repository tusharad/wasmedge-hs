-- | Tests for WasmEdge version functions
module Test.Unit.VersionSpec (spec) where

import Data.List (isPrefixOf)
import Foreign.C (peekCString)
import Test.Hspec
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

  it "VersionGetMinor returns 18 for WasmEdge 0.18.1" $ do
    minor <- c_VersionGetMinor
    minor `shouldBe` 18

  it "VersionGetPatch returns 1 for WasmEdge 0.18.1" $ do
    patch <- c_VersionGetPatch
    patch `shouldBe` 1

  it "version components are consistent with version string" $ do
    cs <- c_VersionGet
    str <- peekCString cs
    major <- c_VersionGetMajor
    minor <- c_VersionGetMinor
    patch <- c_VersionGetPatch
    let expected = show major ++ "." ++ show minor ++ "." ++ show patch
    str `shouldBe` expected
