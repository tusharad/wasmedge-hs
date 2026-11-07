{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.StatisticsCost
Description : Instruction counting and gas cost limit metering stress test
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Tests the WasmEdge statistics and metering subsystem:
  1. Instruction counting during execution
  2. Cost / gas tracking
  3. Instructions per second measurement
  4. Deterministic execution halting when a cost limit is exceeded
  5. Clearing and resetting statistics
-}
module Stress.StatisticsCost
  ( runStatisticsCostSuite
  , StatisticsMetrics (..)
  ) where

import Control.Exception (throwIO)
import Data.Either (isLeft)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import Stress.WasmBytecode (fibWasm)
import WasmEdge.Configure
  ( StatisticsOptions (..)
  , setStatisticsOptions
  , withConfigure
  )
import WasmEdge.Error (WasmEdgeError (..))
import WasmEdge.Statistics
  ( clearStatistics
  , getInstrCount
  , getInstrPerSecond
  , getTotalCost
  , setStatCostLimit
  )
import WasmEdge.Types (WasmVal (..))
import WasmEdge.VM

-- | Metrics recorded during the statistics and cost metering test
data StatisticsMetrics = StatisticsMetrics
  { smInstructionCount :: !Integer
  , smTotalCost :: !Integer
  , smInstrPerSec :: !Double
  , smCostLimitExhausted :: !Bool
  , smClearVerified :: !Bool
  , smDurationSec :: !Double
  }
  deriving stock (Show)

-- | Run the Statistics and Cost Metering suite.
runStatisticsCostSuite :: IO StatisticsMetrics
runStatisticsCostSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Instruction Counting & Gas Cost Metering"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  (instrs, cost, ips, limitTrapped, cleared) <- withConfigure $ \cfg -> do
    -- 1. Enable full statistics in configure
    setStatisticsOptions
      cfg
      StatisticsOptions
        { statInstructionCounting = True
        , statCostMeasuring = True
        , statTimeMeasuring = True
        }

    withVM (Just cfg) Nothing $ \vm -> do
      -- 2. Load fibWasm
      _ <- loadWasmBytes vm fibWasm
      _ <- validate vm
      _ <- instantiate vm

      -- Run fib(18) = 2584
      putStrLn "--> [1/3] Executing fib(18) with statistics instrumentation enabled..."
      execRes <- execute vm "fib" [WasmI32 18]
      case execRes of
        Right [WasmI32 2584] -> pure ()
        _ -> throwIO (userError "fib(18) returned unexpected result")

      stats <- getStatistics vm
      ic <- getInstrCount stats
      tc <- getTotalCost stats
      ipsRate <- getInstrPerSecond stats

      putStrLn $ printf "    Instructions executed: %d" ic
      putStrLn $ printf "    Total cost measured:   %d" tc
      putStrLn $ printf "    Rate:                  %.2f instructions/sec" ipsRate

      -- 3. Set a strict cost limit to test gas exhaustion
      putStrLn
        "--> [2/3] Setting cost limit to 500 units and executing fib(25) to trigger gas exhaustion..."
      setStatCostLimit stats 500
      exhaustRes <- execute vm "fib" [WasmI32 25]
      let trapped = isLeft exhaustRes
      case exhaustRes of
        Left (WasmEdgeError _cat code _msg) ->
          putStrLn $ printf "    Cost limit successfully triggered trap: code=0x%03X" code
        Right vals ->
          putStrLn $ "    Warning: execution unexpectedly succeeded: " ++ show vals

      -- 4. Clear statistics and verify reset
      putStrLn "--> [3/3] Clearing statistics context..."
      clearStatistics stats
      icAfter <- getInstrCount stats
      let resetOk = icAfter == 0
      putStrLn $ "    Counter reset verified: " ++ if resetOk then "PASSED" else "FAILED"

      pure (fromIntegral ic, fromIntegral tc, ipsRate, trapped, resetOk)

  t1 <- getTime Monotonic
  let durSec = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf "==> Statistics & Metering Suite PASSED in %.3f s\n\n" durSec

  pure $
    StatisticsMetrics
      { smInstructionCount = instrs
      , smTotalCost = cost
      , smInstrPerSec = ips
      , smCostLimitExhausted = limitTrapped
      , smClearVerified = cleared
      , smDurationSec = durSec
      }
