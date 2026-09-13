{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.AsyncTimeout
Description : Stress testing asynchronous execution, timeouts, and cancellation
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Validates non-blocking async execution, timeout detection via 'waitFor',
clean cancellation of infinite loops / runaway guest executions via 'cancel',
and parallel async operations across multiple VM instances.
-}
module Stress.AsyncTimeout
  ( runAsyncTimeoutSuite
  , AsyncMetrics (..)
  ) where

import Control.Concurrent.Async (forConcurrently)
import Control.Exception (throwIO)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import Stress.WasmBytecode (chaosWasm, fibWasm)
import WasmEdge.Async qualified as Async
import WasmEdge.Types (WasmVal (..))
import WasmEdge.VM

-- | Metrics recorded during the async & timeout stress tests.
data AsyncMetrics = AsyncMetrics
  { amNormalDurationSec :: !Double
  , amCancelClean :: !Bool
  , amConcurrentRuns :: !Int
  , amTotalDurationSec :: !Double
  }
  deriving stock (Show)

-- | Run the Async, Timeout, and Cancellation stress suite.
runAsyncTimeoutSuite :: IO AsyncMetrics
runAsyncTimeoutSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Asynchronous Execution, Timeouts & Cancellation"
  putStrLn "============================================================"

  startTotal <- getTime Monotonic

  -- 1. Normal async execution with getReturns
  putStrLn "--> [1/3] Normal async execution of fib(24)..."
  t0 <- getTime Monotonic
  normalRes <- withVM Nothing Nothing $ \vm -> do
    _ <- loadWasmBytes vm fibWasm
    _ <- validate vm
    _ <- instantiate vm
    asyncHandle <- asyncExecute vm "fib" [WasmI32 24]
    -- Wait for completion and fetch return values
    res <- Async.getReturns asyncHandle
    case res of
      Left err -> throwIO (userError $ "Async execution failed: " ++ show err)
      Right [WasmI32 v]
        | v == 46368 -> pure v
        | otherwise -> throwIO (userError $ "Incorrect async fib result: " ++ show v)
      Right other -> throwIO (userError $ "Unexpected return: " ++ show other)
  t1 <- getTime Monotonic
  let normalSec = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  putStrLn $ printf "    Async fib(24) = %d completed successfully in %.3f s" normalRes normalSec

  -- 2. Runaway execution cancellation test (infinite loop)
  putStrLn "--> [2/3] Runaway guest execution timeout & cancellation test..."
  cancelSuccess <- withVM Nothing Nothing $ \vm -> do
    _ <- loadWasmBytes vm chaosWasm
    _ <- validate vm
    _ <- instantiate vm
    putStrLn "    Launching 'infinite_loop' in background async task..."
    asyncHandle <- asyncExecute vm "infinite_loop" []
    -- Wait up to 50ms
    ready50ms <- Async.waitFor asyncHandle 50
    if ready50ms
      then throwIO (userError "Infinite loop unexpectedly finished within 50ms!")
      else putStrLn "    Timeout verified: guest function still running after 50ms"
    -- Cancel the runaway execution
    putStrLn "    Sending cancel signal..."
    Async.cancel asyncHandle
    -- Wait for background thread to cleanly exit
    Async.wait asyncHandle
    putStrLn "    Background thread joined successfully after cancellation"
    pure True

  -- 3. Concurrent Async Runs: 10 parallel VMs running async tasks
  putStrLn "--> [3/3] 10 concurrent async executions across independent VMs..."
  let parallelRuns = 10 :: Int
  results <- forConcurrently [1 .. parallelRuns] $ \i -> do
    withVM Nothing Nothing $ \vm -> do
      _ <- loadWasmBytes vm fibWasm
      _ <- validate vm
      _ <- instantiate vm
      let n = 15 + fromIntegral (i `mod` 5)
      asyncH <- asyncExecute vm "fib" [WasmI32 n]
      res <- Async.getReturns asyncH
      case res of
        Right [WasmI32 v] -> pure v
        _ -> throwIO (userError "Parallel async failed")
  putStrLn $
    printf "    Completed %d parallel async executions: all returned valid results" (length results)

  endTotal <- getTime Monotonic
  let totalSec = fromIntegral (toNanoSecs (diffTimeSpec endTotal startTotal)) / 1e9 :: Double
  printf "==> Async & Cancellation Suite PASSED in %.3f s\n\n" totalSec

  pure $
    AsyncMetrics
      { amNormalDurationSec = normalSec
      , amCancelClean = cancelSuccess
      , amConcurrentRuns = parallelRuns
      , amTotalDurationSec = totalSec
      }
