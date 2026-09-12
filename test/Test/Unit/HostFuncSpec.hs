{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Tests for Host Functions, ToHostFunc typeclass, and Caller memory access
module Test.Unit.HostFuncSpec (spec) where

import Data.ByteString qualified as BS
import Data.Int (Int32)
import Data.Word (Word32)
import Test.Hspec

import WasmEdge
import WasmEdge.Caller
import WasmEdge.Function
import WasmEdge.Module

spec :: Spec
spec = describe "Host functions and Caller" $ do
  describe "ToHostFunc automatic signature and invocation" $ do
    it "creates host function for (Int32 -> Int32 -> IO Int32)" $ do
      fn <- createHostFunction $ \(x :: Int32) (y :: Int32) -> pure (x + 2 * y) :: IO Int32
      fnType <- getFunctionType fn
      params <- getFunctionTypeParameters fnType
      returns <- getFunctionTypeReturns fnType
      params `shouldBe` [I32, I32]
      returns `shouldBe` [I32]
      deleteFunction fn

    it "creates host function for 0-arg IO Int32" $ do
      fn <- createHostFunction (pure 1234 :: IO Int32)
      fnType <- getFunctionType fn
      params <- getFunctionTypeParameters fnType
      returns <- getFunctionTypeReturns fnType
      params `shouldBe` []
      returns `shouldBe` [I32]
      deleteFunction fn

    it "builds a host module with builderAddHostFunc" $ do
      modInst <- buildHostModule "host_math" $ \b -> do
        builderAddHostFunc b "add" $ \(x :: Int32) (y :: Int32) -> pure (x + y) :: IO Int32
        builderAddHostFunc b "sub" $ \(x :: Int32) (y :: Int32) -> pure (x - y) :: IO Int32
        builderAddHostFunc b "answer" (pure 42 :: IO Int32)
      deleteModuleInstance modInst

  describe "VMConfig declarative configuration" $ do
    it "creates and runs VM with defaultVMConfig" $ do
      res <- withVMConfig defaultVMConfig $ \vm -> do
        -- Run an empty WASM module
        let emptyModule = BS.pack [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
        runWasmBytes vm emptyModule "nonexistent" []
      case res of
        Left err -> weErrCategory err `shouldBe` ErrCategory_WASM
        Right _ -> expectationFailure "Expected function not found error"

  describe "Caller memory helpers" $ do
    it "handles null caller gracefully" $ do
      fn <- createHostFunction $ \frame (ptr :: Word32) (len :: Word32) -> do
        mBytes <- readCallerMemory frame 0 ptr len
        pure (case mBytes of Just _ -> 1 :: Int32; Nothing -> 0 :: Int32) :: IO Int32
      deleteFunction fn
