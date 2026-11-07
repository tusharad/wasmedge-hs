-- | Test suite entry point for wasmedge-hs
module Main (main) where

import Test.Hspec

import Test.Property.StringProp qualified as StringProp
import Test.Property.ValueProp qualified as ValueProp
import Test.Unit.ConfigureSpec qualified as Configure
import Test.Unit.HostFuncSpec qualified as HostFunc
import Test.Unit.LiftMemFuncSpec qualified as LiftMemFunc
import Test.Unit.OwnershipSpec qualified as Ownership
import Test.Unit.VMSpec qualified as VM
import Test.Unit.ValueSpec qualified as Value
import Test.Unit.VersionSpec qualified as Version
import Test.Unit.WasmMemorySpec qualified as WasmMemory

main :: IO ()
main = hspec $ do
  describe "Version" Version.spec
  describe "Configure" Configure.spec
  describe "Value" Value.spec
  describe "VM" VM.spec
  describe "HostFunc" HostFunc.spec
  describe "Ownership" Ownership.spec
  describe "WasmMemory" WasmMemory.spec
  describe "LiftMemFunc" LiftMemFunc.spec
  describe "Properties" $ do
    ValueProp.spec
    StringProp.spec
