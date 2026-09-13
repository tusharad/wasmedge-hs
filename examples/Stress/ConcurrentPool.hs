{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.ConcurrentPool
Description : High-concurrency VM worker pool and throughput stress testing
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Tests high-concurrency execution across multiple GHC capabilities and OS threads.
Implements a production-grade 'VMPool' with bounded queuing ('TBQueue'), and compares
reusable pooled VMs against ephemeral (per-request) VMs under heavy load (1,000+ requests).
Computes throughput (ops/sec) and p50/p95/p99 latency distributions.
-}
module Stress.ConcurrentPool
  ( runConcurrentPoolSuite
  , ConcurrentMetrics (..)
  , VMPool (..)
  , createVMPool
  , withPooledVM
  , destroyVMPool
  ) where

import Control.Concurrent.Async (forConcurrently)
import Control.Concurrent.STM
  ( TBQueue
  , atomically
  , newTBQueueIO
  , readTBQueue
  , tryReadTBQueue
  , writeTBQueue
  )
import Control.Exception (bracket, throwIO)
import Control.Monad (replicateM)
import Data.List (sort)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import Stress.WasmBytecode (addWasm, fibWasm)
import WasmEdge.Types (WasmVal (..))
import WasmEdge.VM

-- | Production VM Pool backed by a thread-safe STM bounded queue.
newtype VMPool = VMPool (TBQueue VM)

-- | Create a VM pool with @size@ pre-allocated and initialized VMs.
createVMPool :: Int -> IO VMPool
createVMPool size = do
  q <- newTBQueueIO (fromIntegral size)
  vms <- replicateM size $ do
    vm <- createVM Nothing Nothing
    -- Pre-load and instantiate fibWasm
    loadRes <- loadWasmBytes vm fibWasm
    case loadRes of
      Left err -> throwIO (userError $ "Failed to load fibWasm in pool: " ++ show err)
      Right () -> pure ()
    valRes <- validate vm
    case valRes of
      Left err -> throwIO (userError $ "Failed to validate fibWasm in pool: " ++ show err)
      Right () -> pure ()
    instRes <- instantiate vm
    case instRes of
      Left err -> throwIO (userError $ "Failed to instantiate fibWasm in pool: " ++ show err)
      Right () -> pure ()
    pure vm
  atomically $ mapM_ (writeTBQueue q) vms
  pure (VMPool q)

-- | Borrow a VM from the pool, execute an action, and safely return it.
withPooledVM :: VMPool -> (VM -> IO a) -> IO a
withPooledVM (VMPool q) =
  bracket
    (atomically $ readTBQueue q)
    (atomically . writeTBQueue q)

-- | Destroy all VMs in the pool.
destroyVMPool :: VMPool -> IO ()
destroyVMPool (VMPool q) = do
  mVM <- atomically $ tryReadTBQueue q
  case mVM of
    Nothing -> pure ()
    Just vm -> do
      deleteVM vm
      destroyVMPool (VMPool q)

-- | Benchmark metrics for a concurrency run.
data ConcurrentMetrics = ConcurrentMetrics
  { cmTotalRequests :: !Int
  , cmConcurrency :: !Int
  , cmDurationSec :: !Double
  , cmThroughputRPS :: !Double
  , cmP50LatencyMs :: !Double
  , cmP95LatencyMs :: !Double
  , cmP99LatencyMs :: !Double
  , cmMaxLatencyMs :: !Double
  }
  deriving stock (Show)

-- | Helper to compute percentile from a sorted list of latencies in milliseconds.
percentile :: Double -> [Double] -> Double
percentile _ [] = 0.0
percentile p xs =
  let idx = floor (p * fromIntegral (length xs - 1))
   in xs !! idx

-- | Run the high-concurrency stress test suite.
runConcurrentPoolSuite :: IO (ConcurrentMetrics, ConcurrentMetrics)
runConcurrentPoolSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: High-Concurrency & VM Pool Throughput"
  putStrLn "============================================================"

  let totalTasks = 1000 :: Int
      poolSize = 16 :: Int
      fibArg = 20 :: Int -- fib(20) = 6765
      expectedFib = 6765 :: Int

  -- -------------------------------------------------------------
  -- Test A: Pooled VMs (amortized instantiation cost)
  -- -------------------------------------------------------------
  putStrLn $
    printf
      "--> [1/2] Pooled VMs: running %d concurrent requests across %d pooled VMs..."
      totalTasks
      poolSize
  pool <- createVMPool poolSize

  startA <- getTime Monotonic
  latenciesA <- forConcurrently [1 .. totalTasks] $ \_ -> do
    t0 <- getTime Monotonic
    res <- withPooledVM pool $ \vm ->
      execute vm "fib" [WasmI32 (fromIntegral fibArg)]
    t1 <- getTime Monotonic
    case res of
      Left err -> throwIO (userError $ "Pooled execution failed: " ++ show err)
      Right [WasmI32 v]
        | fromIntegral v == expectedFib -> pure ()
        | otherwise -> throwIO (userError $ "Incorrect fib result: " ++ show v)
      Right other -> throwIO (userError $ "Unexpected return: " ++ show other)
    let nanos = toNanoSecs (diffTimeSpec t1 t0)
    pure (fromIntegral nanos / 1e6 :: Double)
  endA <- getTime Monotonic

  let durNanosA = toNanoSecs (diffTimeSpec endA startA)
      durSecA = fromIntegral durNanosA / 1e9 :: Double
      rpsA = fromIntegral totalTasks / durSecA
      sortedLatA = sort latenciesA
      p50A = percentile 0.50 sortedLatA
      p95A = percentile 0.95 sortedLatA
      p99A = percentile 0.99 sortedLatA
      maxLatA = if null sortedLatA then 0.0 else last sortedLatA

  printf "    Pooled Results: %.2f req/sec (%.3f s total)\n" rpsA durSecA
  printf
    "    Latencies: p50 = %.3f ms | p95 = %.3f ms | p99 = %.3f ms | max = %.3f ms\n\n"
    p50A
    p95A
    p99A
    maxLatA
  destroyVMPool pool

  -- -------------------------------------------------------------
  -- Test B: Ephemeral VMs (Fresh VM created & destroyed per request)
  -- -------------------------------------------------------------
  putStrLn $
    printf
      "--> [2/2] Ephemeral VMs: running %d requests with fresh VM creation & teardown..."
      (totalTasks `div` 2)
  let ephemeralCount = totalTasks `div` 2

  startB <- getTime Monotonic
  latenciesB <- forConcurrently [1 .. ephemeralCount] $ \_ -> do
    t0 <- getTime Monotonic
    res <- withVM Nothing Nothing $ \vm ->
      runWasmBytes vm addWasm "add" [WasmI32 20, WasmI32 22]
    t1 <- getTime Monotonic
    case res of
      Left err -> throwIO (userError $ "Ephemeral execution failed: " ++ show err)
      Right [WasmI32 42] -> pure ()
      Right other -> throwIO (userError $ "Unexpected return: " ++ show other)
    let nanos = toNanoSecs (diffTimeSpec t1 t0)
    pure (fromIntegral nanos / 1e6 :: Double)
  endB <- getTime Monotonic

  let durNanosB = toNanoSecs (diffTimeSpec endB startB)
      durSecB = fromIntegral durNanosB / 1e9 :: Double
      rpsB = fromIntegral ephemeralCount / durSecB
      sortedLatB = sort latenciesB
      p50B = percentile 0.50 sortedLatB
      p95B = percentile 0.95 sortedLatB
      p99B = percentile 0.99 sortedLatB
      maxLatB = if null sortedLatB then 0.0 else last sortedLatB

  printf "    Ephemeral Results: %.2f req/sec (%.3f s total)\n" rpsB durSecB
  printf
    "    Latencies: p50 = %.3f ms | p95 = %.3f ms | p99 = %.3f ms | max = %.3f ms\n\n"
    p50B
    p95B
    p99B
    maxLatB

  let metricsA = ConcurrentMetrics totalTasks poolSize durSecA rpsA p50A p95A p99A maxLatA
      metricsB = ConcurrentMetrics ephemeralCount 1 durSecB rpsB p50B p95B p99B maxLatB
  pure (metricsA, metricsB)
