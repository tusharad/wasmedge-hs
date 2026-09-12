-- | VM integration tests
module Test.Unit.VMSpec (spec) where

import Test.Hspec
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS

import WasmEdge.VM
import WasmEdge.Types

-- Minimal valid WASM module (empty):
-- (module)
emptyWasm :: ByteString
emptyWasm = BS.pack
  [ 0x00, 0x61, 0x73, 0x6D  -- magic: \0asm
  , 0x01, 0x00, 0x00, 0x00  -- version: 1
  ]

-- Minimal add function WASM:
-- (module
--   (func (export "add") (param i32 i32) (result i32)
--     local.get 0
--     local.get 1
--     i32.add))
addWasm :: ByteString
addWasm = BS.pack
  [ 0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00
  -- type section: (i32 i32) -> (i32)
  , 0x01, 0x07, 0x01, 0x60, 0x02, 0x7F, 0x7F, 0x01, 0x7F
  -- function section: func 0
  , 0x03, 0x02, 0x01, 0x00
  -- export section: "add" -> func 0
  , 0x07, 0x07, 0x01, 0x03, 0x61, 0x64, 0x64, 0x00, 0x00
  -- code section
  , 0x0A, 0x09, 0x01, 0x07, 0x00
    , 0x20, 0x00  -- local.get 0
    , 0x20, 0x01  -- local.get 1
    , 0x6A        -- i32.add
    , 0x0B        -- end
  ]

spec :: Spec
spec = describe "WasmEdge VM" $ do

  it "creates and deletes VM without crashing" $
    withVM Nothing Nothing $ \_ -> pure ()

  describe "runWasmBytes" $ do
    it "runs empty module without crashing" $
      withVM Nothing Nothing $ \vm -> do
        -- Running an empty module with a non-existent function should return Left
        r <- runWasmBytes vm emptyWasm "nonexistent" []
        r `shouldSatisfy` isLeft

    it "add(3, 4) = 7" $
      withVM Nothing Nothing $ \vm -> do
        r <- runWasmBytes vm addWasm "add" [WasmI32 3, WasmI32 4]
        case r of
          Left err -> expectationFailure $ "Expected success, got: " ++ show err
          Right [WasmI32 7] -> pure ()
          Right other -> expectationFailure $ "Expected [WasmI32 7], got: " ++ show other

    it "add(maxBound, 1) wraps to minBound" $
      withVM Nothing Nothing $ \vm -> do
        r <- runWasmBytes vm addWasm "add" [WasmI32 maxBound, WasmI32 1]
        case r of
          Left err -> expectationFailure $ show err
          Right [WasmI32 v] -> v `shouldBe` minBound
          Right other -> expectationFailure $ "Unexpected: " ++ show other

  describe "load/validate/instantiate/execute pipeline" $ do
    it "runs the step-by-step pipeline correctly" $
      withVM Nothing Nothing $ \vm -> do
        loadR <- loadWasmBytes vm addWasm
        loadR `shouldBe` Right ()
        valR <- validate vm
        valR `shouldBe` Right ()
        instR <- instantiate vm
        instR `shouldBe` Right ()
        r <- execute vm "add" [WasmI32 10, WasmI32 20]
        case r of
          Left err -> expectationFailure $ show err
          Right [WasmI32 30] -> pure ()
          Right other -> expectationFailure $ "Got: " ++ show other

  describe "error propagation" $ do
    it "returns Left for invalid WASM bytes" $
      withVM Nothing Nothing $ \vm -> do
        r <- loadWasmBytes vm (BS.pack [0x00, 0x01, 0x02, 0x03])
        r `shouldSatisfy` isLeft

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _        = False
