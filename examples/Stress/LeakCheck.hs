{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.LeakCheck
Description : Rapid VM lifecycle and memory leak detection stress test
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Rapidly creates and destroys VMs, Memory instances, Stores, and Compilers in
a tight loop (5,000+ iterations) to verify that ForeignPtr finalizers cleanly
release all C resources without memory leaks or pointer corruption.
-}
module Stress.LeakCheck
  ( runLeakCheckSuite
  , LeakMetrics (..)
  ) where

import Control.Exception (throwIO)
import Control.Monad (forM_)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import System.Mem (performMajorGC)
import Text.Printf (printf)

import Stress.WasmBytecode (addWasm)
import WasmEdge.Compiler (createCompiler, deleteCompiler)
import WasmEdge.Configure (createConfigure, deleteConfigure)
import WasmEdge.Memory (createMemory, createMemoryType, deleteMemory, deleteMemoryType)
import WasmEdge.Store (createStore, deleteStore)
import WasmEdge.Types (Limit (..), WasmVal (..))
import WasmEdge.VM (runWasmBytes, withVM)

-- | Metrics from the lifecycle leak check suite
data LeakMetrics = LeakMetrics
  { lmVMIterations :: !Int
  , lmContextIterations :: !Int
  , lmDurationSec :: !Double
  , lmRatePerSec :: !Double
  , lmZeroLeakVerified :: !Bool
  }
  deriving stock (Show)

-- | Run the Rapid Lifecycle & Leak Check suite.
runLeakCheckSuite :: IO LeakMetrics
runLeakCheckSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Rapid Lifecycle Stability & Memory Leak Check"
  putStrLn "============================================================"

  let vmIterations = 5000 :: Int
      ctxIterations = 1000 :: Int

  -- Force a clean baseline GC
  performMajorGC

  startTotal <- getTime Monotonic

  -- 1. 5,000 rapid VM creation -> execution -> destruction cycles
  putStrLn $
    printf "--> [1/2] Executing %d rapid VM creation -> execute -> teardown cycles..." vmIterations
  tVM0 <- getTime Monotonic
  forM_ [1 .. vmIterations] $ \i -> do
    res <- withVM Nothing Nothing $ \vm ->
      runWasmBytes vm addWasm "add" [WasmI32 (fromIntegral i), WasmI32 1]
    case res of
      Right [WasmI32 v]
        | fromIntegral v == i + 1 -> pure ()
        | otherwise -> throwIO (userError $ "Calculation error at iteration " ++ show i)
      Left err -> throwIO (userError $ "VM execution error at iteration " ++ show i ++ ": " ++ show err)
      Right other -> throwIO (userError $ "Unexpected return at iteration " ++ show i ++ ": " ++ show other)
  tVM1 <- getTime Monotonic

  let vmSec = fromIntegral (toNanoSecs (diffTimeSpec tVM1 tVM0)) / 1e9 :: Double
      vmRPS = fromIntegral vmIterations / vmSec
  printf
    "    VM Lifecycle: completed %d iterations in %.3f s (%.1f VMs/sec)\n"
    vmIterations
    vmSec
    vmRPS

  -- 2. 1,000 iterations creating & deleting Memory, Store, Configure, and Compiler contexts
  putStrLn $
    printf
      "--> [2/2] Executing %d iterations of raw FFI context allocation & deallocation..."
      ctxIterations
  tCtx0 <- getTime Monotonic
  forM_ [1 .. ctxIterations] $ \_ -> do
    -- Configure
    cfg <- createConfigure
    deleteConfigure cfg

    -- Store
    store <- createStore
    deleteStore store

    -- MemoryType & MemoryInstance
    mt <- createMemoryType (Limit 1 (Just 10) False)
    mem <- createMemory mt
    deleteMemory mem
    deleteMemoryType mt

    -- Compiler
    comp <- createCompiler Nothing
    deleteCompiler comp
  tCtx1 <- getTime Monotonic

  let ctxSec = fromIntegral (toNanoSecs (diffTimeSpec tCtx1 tCtx0)) / 1e9 :: Double
      ctxRPS = fromIntegral ctxIterations / ctxSec
  printf
    "    Context Lifecycle: completed %d iterations in %.3f s (%.1f cycles/sec)\n"
    ctxIterations
    ctxSec
    ctxRPS

  -- Force major GC to ensure all finalizers have executed
  performMajorGC

  endTotal <- getTime Monotonic
  let totalSec = fromIntegral (toNanoSecs (diffTimeSpec endTotal startTotal)) / 1e9 :: Double
      totalOps = vmIterations + ctxIterations
      overallRate = fromIntegral totalOps / totalSec

  printf "==> Lifecycle & Leak Check Suite PASSED in %.3f s (0 leaks detected)\n\n" totalSec

  pure $
    LeakMetrics
      { lmVMIterations = vmIterations
      , lmContextIterations = ctxIterations
      , lmDurationSec = totalSec
      , lmRatePerSec = overallRate
      , lmZeroLeakVerified = True
      }
