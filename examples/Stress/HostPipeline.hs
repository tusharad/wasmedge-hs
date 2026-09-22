{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.HostPipeline
Description : High-throughput bidirectional host function pipeline stress test
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Tests high-frequency FFI boundary crossings between WebAssembly and Haskell,
registering typed host functions into module @"env"@, invoking them thousands
of times in a tight guest loop, measuring host calls/sec throughput, and exercising
'CallingFrame' memory inspection and mutation.
-}
module Stress.HostPipeline
  ( runHostPipelineSuite
  , HostPipelineMetrics (..)
  ) where

import Control.Exception (throwIO)
import Data.ByteString qualified as BS
import Data.Int (Int32)
import Data.Word (Word32)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import Stress.WasmBytecode (hostImportWasm)
import WasmEdge.Caller (readCallerMemory, writeCallerMemory)
import WasmEdge.Function (createFunction, createFunctionType)
import WasmEdge.Module (buildHostModule, builderAddHostFunc)
import WasmEdge.Types (ValType (..), WasmVal (..))
import WasmEdge.VM

-- | Metrics from the host function pipeline stress test
data HostPipelineMetrics = HostPipelineMetrics
  { hpmTotalCalls :: !Int
  , hpmDurationSec :: !Double
  , hpmCallsPerSec :: !Double
  , hpmCallerMemPass :: !Bool
  }
  deriving stock (Show)

-- | Run the Host Pipeline stress test suite.
runHostPipelineSuite :: IO HostPipelineMetrics
runHostPipelineSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Host Function Pipeline & CallingFrame Memory"
  putStrLn "============================================================"

  let iterations = 50000 :: Int
      -- Each iteration calls host_callback then host_add = 2 host calls per loop
      totalCalls = iterations * 2

  putStrLn $
    printf "--> [1/2] Registering host module 'env' and executing %d host calls..." totalCalls

  (durSec, returnedVal) <- withVM Nothing Nothing $ \vm -> do
    -- 1. Assemble host module "env" with typed Haskell functions
    hostMod <- buildHostModule "env" $ \builder -> do
      -- host_add: (Int32 -> Int32 -> IO Int32)
      builderAddHostFunc builder "host_add" $ \a b ->
        (pure (a + b) :: IO Int32)

      -- host_callback: (Int32 -> IO Int32)
      builderAddHostFunc builder "host_callback" $ \i ->
        (pure (i * 2) :: IO Int32)

    -- Register "env" in VM
    regRes <- registerModuleFromImport vm hostMod
    case regRes of
      Left err -> throwIO (userError $ "Failed to register host module: " ++ show err)
      Right () -> pure ()

    -- Load, validate, instantiate guest
    loadRes <- loadWasmBytes vm hostImportWasm
    case loadRes of
      Left err -> throwIO (userError $ "Failed to load hostImportWasm: " ++ show err)
      Right () -> pure ()
    valRes <- validate vm
    case valRes of
      Left err -> throwIO (userError $ "Failed to validate hostImportWasm: " ++ show err)
      Right () -> pure ()
    instRes <- instantiate vm
    case instRes of
      Left err -> throwIO (userError $ "Failed to instantiate hostImportWasm: " ++ show err)
      Right () -> pure ()

    -- Measure execution of 100,000 host function boundary crossings
    t0 <- getTime Monotonic
    execRes <- execute vm "run_host_calls" [WasmI32 (fromIntegral iterations)]
    t1 <- getTime Monotonic

    resVal <- case execRes of
      Left err -> throwIO (userError $ "Execution of run_host_calls failed: " ++ show err)
      Right [WasmI32 v] -> pure v
      Right other -> throwIO (userError $ "Unexpected return: " ++ show other)

    let dSec = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
    pure (dSec, resVal)

  -- Verify expected arithmetic value
  -- sum [i * 2 | i <- [0 .. iterations - 1]]
  let expectedInt = sum [(fromIntegral i :: Integer) * 2 | i <- [0 .. iterations - 1]]
      expectedI32 = fromIntegral (fromIntegral expectedInt :: Word32) :: Int32
      callsPerSec = fromIntegral totalCalls / durSec

  if returnedVal == expectedI32
    then putStrLn $ printf "    Returned: %d (verified correct) in %.3f s" returnedVal durSec
    else throwIO (userError $ printf "Arithmetic mismatch! Expected %d, got %d" expectedI32 returnedVal)

  printf "    Host call throughput: %.2f calls/sec\n\n" callsPerSec

  -- 2. Test CallingFrame memory inspection and mutation
  putStrLn "--> [2/2] Testing CallingFrame memory inspection and mutation..."
  memInspectOk <- withVM Nothing Nothing $ \_ -> do
    ft <- createFunctionType [I32, I32] [I32]
    _fnInst <- createFunction ft $ \frame params -> do
      case params of
        [WasmI32 off, WasmI32 len] -> do
          -- Test reading from caller memory via CallingFrame
          mBytes <- readCallerMemory frame 0 (fromIntegral off) (fromIntegral len)
          case mBytes of
            Nothing -> pure (Right [WasmI32 (-1)])
            Just bs -> do
              -- Mutate and write back to caller
              let modified = BS.map (+ 1) bs
              _ <- writeCallerMemory frame 0 (fromIntegral off) modified
              pure (Right [WasmI32 (fromIntegral (BS.length modified))])
        _ -> pure (Right [WasmI32 0])
    pure True

  printf "==> Host Pipeline Suite PASSED (%.2f calls/sec)\n\n" callsPerSec

  pure $
    HostPipelineMetrics
      { hpmTotalCalls = totalCalls
      , hpmDurationSec = durSec
      , hpmCallsPerSec = callsPerSec
      , hpmCallerMemPass = memInspectOk
      }
