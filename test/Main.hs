-- | Test suite entry point for wasmedge-hs
module Main (main) where

import Test.Hspec

import qualified Test.Unit.VersionSpec    as Version
import qualified Test.Unit.ConfigureSpec  as Configure
import qualified Test.Unit.ValueSpec      as Value
import qualified Test.Unit.VMSpec         as VM
import qualified Test.Unit.OwnershipSpec  as Ownership
import qualified Test.Property.ValueProp  as ValueProp
import qualified Test.Property.StringProp as StringProp

main :: IO ()
main = hspec $ do
  describe "Version"    Version.spec
  describe "Configure"  Configure.spec
  describe "Value"      Value.spec
  describe "VM"         VM.spec
  describe "Ownership"  Ownership.spec
  describe "Properties" $ do
    ValueProp.spec
    StringProp.spec
