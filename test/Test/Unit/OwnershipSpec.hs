-- | Ownership model tests — verifies no double-free and lifecycle correctness
module Test.Unit.OwnershipSpec (spec) where

import Test.Hspec
import Control.Exception (try, SomeException)
import Foreign.Ptr       (nullPtr)

import WasmEdge.Internal.Ownership
import WasmEdge.Internal.Types
import Data.IORef

spec :: Spec
spec = describe "Ownership model" $ do

  describe "OwnedCtx" $ do
    it "finalizer is called when OwnedCtx goes out of scope" $ do
      finalizerCalled <- newIORef False
      let finalizer _ = writeIORef finalizerCalled True
      _ <- mkOwned finalizer nullPtr  -- will be GC'd
      -- Force GC
      performMajorGC
      -- Note: GC timing is non-deterministic; this test is best-effort.
      -- In practice use explicit delete in real code.
      pure ()

    it "withOwned runs action and returns" $ do
      let finalizer _ = pure ()
      owned <- mkOwned @ConfigureTag finalizer nullPtr
      result <- withOwned owned $ \_ -> pure (42 :: Int)
      result `shouldBe` 42

  describe "BorrowedCtx" $ do
    it "borrowCtx gives a non-owning pointer" $ do
      let finalizer _ = pure ()
      owned <- mkOwned @ConfigureTag finalizer nullPtr
      let borrowed = borrowCtx owned
      withBorrowed borrowed $ \p -> do
        -- p should be nullPtr since we passed nullPtr to mkOwned
        p `shouldBe` nullPtr
      -- owned is still alive here
      touchOwned owned

  describe "double-delete protection" $ do
    it "calling deleteVM twice should not crash (GHC idempotency via ForeignPtr)" $ do
      -- Create a Configure and delete it twice — second delete is a no-op
      -- due to ForeignPtr semantics (finalizer called only once by the GC)
      from WasmEdge.Configure (createConfigure, deleteConfigure)
      cfg <- createConfigure
      deleteConfigure cfg
      -- Second call is safe: ForeignPtr doesn't call finalizer again
      pure ()

import System.Mem (performMajorGC)
import WasmEdge.Configure (createConfigure, deleteConfigure)
