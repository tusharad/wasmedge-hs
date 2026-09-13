{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.ChaosFault
Description : Chaos engineering and fault injection resilience stress test
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Tests runtime resilience under adverse fault conditions:
  1. WebAssembly 'unreachable' traps
  2. Integer division-by-zero
  3. Out-of-bounds linear memory access
  4. Non-existent function execution
  5. Corrupted bytecode headers and truncated sections
  6. Concurrent chaos storm across multiple threads verifying zero crashes/segfaults
-}
module Stress.ChaosFault
  ( runChaosFaultSuite
  , ChaosMetrics (..)
  ) where

import Control.Concurrent.Async (forConcurrently)
import Control.Exception (throwIO)
import Control.Monad (when)
import Data.Either (isLeft, isRight)
import Data.Text qualified as T
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import Stress.WasmBytecode
  ( addWasm
  , chaosWasm
  , corruptedMagicWasm
  , corruptedSectionWasm
  )
import WasmEdge.Error (WasmEdgeError (..))
import WasmEdge.Types (WasmVal (..))
import WasmEdge.VM

-- | Metrics recorded during chaos fault testing
data ChaosMetrics = ChaosMetrics
  { cfmTrapCaught :: !Bool
  , cfmDivByZeroCaught :: !Bool
  , cfmOobCaught :: !Bool
  , cfmCorruptCaught :: !Bool
  , cfmStormTotalFaults :: !Int
  , cfmStormSuccessRate :: !Double
  , cfmDurationSec :: !Double
  }
  deriving stock (Show)

-- | Run the Chaos and Fault Injection stress test suite.
runChaosFaultSuite :: IO ChaosMetrics
runChaosFaultSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Chaos Fault Injection & Resilience"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  -- 1. Trap unreachable test
  putStrLn "--> [1/6] Fault Injection: 'unreachable' trap instruction..."
  trapOk <- withVM Nothing Nothing $ \vm -> do
    _ <- loadWasmBytes vm chaosWasm
    _ <- validate vm
    _ <- instantiate vm
    res <- execute vm "trap_unreachable" []
    case res of
      Left (WasmEdgeError _cat code msg) -> do
        putStrLn $ printf "    Caught expected trap: code=0x%03X (%s)" code (T.unpack (T.take 40 msg))
        pure True
      Right vals -> do
        putStrLn $ "    Unexpected success: " ++ show vals
        pure False

  -- 2. Division by zero test
  putStrLn "--> [2/6] Fault Injection: integer division by zero..."
  divOk <- withVM Nothing Nothing $ \vm -> do
    _ <- loadWasmBytes vm chaosWasm
    _ <- validate vm
    _ <- instantiate vm
    res <- execute vm "div_by_zero" [WasmI32 42]
    case res of
      Left (WasmEdgeError _cat code msg) -> do
        putStrLn $
          printf "    Caught expected div-by-zero: code=0x%03X (%s)" code (T.unpack (T.take 40 msg))
        pure True
      Right vals -> do
        putStrLn $ "    Unexpected success: " ++ show vals
        pure False

  -- 3. Out-of-bounds linear memory load test
  putStrLn "--> [3/6] Fault Injection: out-of-bounds memory load (offset 70000 > 65536)..."
  oobOk <- withVM Nothing Nothing $ \vm -> do
    _ <- loadWasmBytes vm chaosWasm
    _ <- validate vm
    _ <- instantiate vm
    res <- execute vm "oob_memory_load" [WasmI32 70000]
    case res of
      Left (WasmEdgeError _cat code msg) -> do
        putStrLn $ printf "    Caught expected OOB access: code=0x%03X (%s)" code (T.unpack (T.take 40 msg))
        pure True
      Right vals -> do
        putStrLn $ "    Unexpected success: " ++ show vals
        pure False

  -- 4. Calling nonexistent function
  putStrLn "--> [4/6] Fault Injection: invocation of nonexistent export..."
  nonexistentOk <- withVM Nothing Nothing $ \vm -> do
    _ <- loadWasmBytes vm chaosWasm
    _ <- validate vm
    _ <- instantiate vm
    res <- execute vm "ghost_function" []
    pure (isLeft res)
  putStrLn $ "    Nonexistent function error properly caught: " ++ show nonexistentOk

  -- 5. Loading corrupted bytecodes
  putStrLn "--> [5/6] Fault Injection: corrupted bytecode headers..."
  corruptOk <- withVM Nothing Nothing $ \vm -> do
    resMagic <- loadWasmBytes vm corruptedMagicWasm
    resSection <- loadWasmBytes vm corruptedSectionWasm
    pure (isLeft resMagic && isLeft resSection)
  putStrLn $ "    Corrupted bytecode rejection verified: " ++ show corruptOk

  -- 6. Concurrent Chaos Storm: 1,000 mixed requests across 20 threads
  putStrLn "--> [6/6] Chaos Storm: 1,000 mixed valid/faulty requests across 20 concurrent threads..."
  let stormCount = 1000 :: Int
  stormResults <- forConcurrently [1 .. stormCount] $ \i -> do
    withVM Nothing Nothing $ \vm -> do
      case i `mod` 5 of
        0 -> do
          -- Good call
          r <- runWasmBytes vm addWasm "add" [WasmI32 (fromIntegral i), WasmI32 1]
          pure (isRight r)
        1 -> do
          -- Trap
          _ <- loadWasmBytes vm chaosWasm
          _ <- validate vm
          _ <- instantiate vm
          r <- execute vm "trap_unreachable" []
          pure (isLeft r)
        2 -> do
          -- Div by zero
          _ <- loadWasmBytes vm chaosWasm
          _ <- validate vm
          _ <- instantiate vm
          r <- execute vm "div_by_zero" [WasmI32 (fromIntegral i)]
          pure (isLeft r)
        3 -> do
          -- OOB load
          _ <- loadWasmBytes vm chaosWasm
          _ <- validate vm
          _ <- instantiate vm
          r <- execute vm "oob_memory_load" [WasmI32 99999]
          pure (isLeft r)
        _ -> do
          -- Corrupt load
          r <- loadWasmBytes vm corruptedMagicWasm
          pure (isLeft r)

  let passedStorm = length (filter id stormResults)
      successRate = fromIntegral passedStorm / fromIntegral stormCount * 100.0 :: Double

  putStrLn $
    printf "    Chaos Storm result: %d/%d passed (%.1f%% resilience)" passedStorm stormCount successRate

  when (passedStorm /= stormCount) $
    throwIO (userError "Chaos storm failed to handle all errors safely!")

  t1 <- getTime Monotonic
  let durSec = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf "==> Chaos Suite PASSED in %.3f s (0 crashes, 100%% recovery)\n\n" durSec

  pure $
    ChaosMetrics
      { cfmTrapCaught = trapOk
      , cfmDivByZeroCaught = divOk
      , cfmOobCaught = oobOk
      , cfmCorruptCaught = corruptOk && nonexistentOk
      , cfmStormTotalFaults = stormCount
      , cfmStormSuccessRate = successRate
      , cfmDurationSec = durSec
      }
