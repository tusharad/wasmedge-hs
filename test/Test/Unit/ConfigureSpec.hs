-- | Unit tests for WasmEdge Configure context
module Test.Unit.ConfigureSpec (spec) where

import Test.Hspec
import WasmEdge.Configure
import WasmEdge.Types

spec :: Spec
spec = describe "WasmEdge Configure" $ do

  it "creates and deletes without crashing" $
    withConfigure $ \_ -> pure ()

  describe "Proposals" $ do
    it "SIMD not enabled by default" $
      withConfigure $ \cfg -> do
        r <- hasProposal cfg SIMD
        r `shouldBe` False

    it "adds and has SIMD" $
      withConfigure $ \cfg -> do
        addProposal cfg SIMD
        r <- hasProposal cfg SIMD
        r `shouldBe` True

    it "removes a proposal" $
      withConfigure $ \cfg -> do
        addProposal cfg Threads
        removeProposal cfg Threads
        r <- hasProposal cfg Threads
        r `shouldBe` False

    it "adding then checking multiple proposals" $
      withConfigure $ \cfg -> do
        mapM_ (addProposal cfg) [SIMD, Threads, FunctionReferences, GC]
        results <- mapM (hasProposal cfg) [SIMD, Threads, FunctionReferences, GC]
        results `shouldBe` [True, True, True, True]

  describe "Memory limits" $ do
    it "sets and gets max memory page" $
      withConfigure $ \cfg -> do
        setMaxMemoryPage cfg 1024
        n <- getMaxMemoryPage cfg
        n `shouldBe` 1024

  describe "Run mode (0.18+)" $ do
    it "defaults to Interpreter" $
      withConfigure $ \cfg -> do
        mode <- getRunMode cfg
        mode `shouldBe` RunModeInterpreter

    it "sets and gets AOT mode" $
      withConfigure $ \cfg -> do
        setRunMode cfg RunModeAOT
        mode <- getRunMode cfg
        mode `shouldBe` RunModeAOT

    it "sets and gets LazyJIT mode" $
      withConfigure $ \cfg -> do
        setRunMode cfg RunModeLazyJIT
        mode <- getRunMode cfg
        mode `shouldBe` RunModeLazyJIT

  describe "Compiler options" $ do
    it "sets optimization level" $
      withConfigure $ \cfg -> do
        setCompilerOptions cfg defaultCompilerOptions { compOptLevel = OptO1 }
        opts <- getCompilerOptions cfg
        compOptLevel opts `shouldBe` OptO1

  describe "Statistics options" $ do
    it "enables instruction counting" $
      withConfigure $ \cfg -> do
        setStatisticsOptions cfg defaultStatisticsOptions { statInstructionCounting = True }
        opts <- getStatisticsOptions cfg
        statInstructionCounting opts `shouldBe` True

  describe "WASM Standard" $ do
    it "sets WASM3 standard" $
      -- Just verify no crash; WASM3 enables many proposals
      withConfigure $ \cfg -> do
        setWasmStandard cfg WASM3
        -- After WASM3, most proposals should be enabled
        r <- hasProposal cfg SIMD
        r `shouldBe` True
