{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.WASILifecycle
Description : Full WASI module instance sandboxing and exit code lifecycle suite
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Exercises:
  * 'createWASIModule' with custom args, envs, and preopens
  * 'withWASIModule' scoped lifecycle
  * 'initWASI' re-initialization
  * 'getWASIExitCode'
  * Registering WASI module into VM and Store
-}
module Stress.WASILifecycle
  ( runWASILifecycleSuite
  , WASILifecycleMetrics (..)
  ) where

import Control.Monad (unless)
import Data.Word (Word32)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import WasmEdge (createVM)
import WasmEdge.Module
  ( createWASIModule
  , getModuleName
  , getWASIExitCode
  , initWASI
  , withWASIModule
  )
import WasmEdge.VM (deleteVM, registerModuleFromImport)

data WASILifecycleMetrics = WASILifecycleMetrics
  { wlmInitialExitCode :: !Word32
  , wlmReinitExitCode :: !Word32
  , wlmScopedSuccess :: !Bool
  , wlmVMRegistrationOK :: !Bool
  , wlmDurationSec :: !Double
  }
  deriving stock (Show)

runWASILifecycleSuite :: IO WASILifecycleMetrics
runWASILifecycleSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: WASI Sandboxing, Exit Codes & Lifecycle"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  -- 1. Create WASI module with custom environment and arguments
  putStrLn "[1/4] Creating WASI module instance with custom args, envs, preopens..."
  let args1 = ["my_guest_program", "--flag", "production_mode"]
      envs1 = ["APP_ENV=prod", "LOG_LEVEL=info", "THREADS=8"]
      preopens1 = [".:.", "/tmp:/tmp"]

  wasiMod <- createWASIModule args1 envs1 preopens1

  wasiModName <- getModuleName wasiMod
  printf "      WASI Module exported name: %s\n" (show wasiModName)

  exitCode1 <- getWASIExitCode wasiMod
  printf "      Initial WASI exit code: %d\n" exitCode1

  -- 2. Test re-initialization via initWASI
  putStrLn "[2/4] Re-initializing WASI module via initWASI with new parameters..."
  let args2 = ["my_guest_program", "--restarted", "true"]
      envs2 = ["APP_ENV=staging", "RETRY_COUNT=3"]
      preopens2 = ["/tmp:/tmp"]

  initWASI wasiMod args2 envs2 preopens2
  exitCode2 <- getWASIExitCode wasiMod
  printf "      Exit code after initWASI: %d\n" exitCode2

  -- 3. Register WASI module into VM
  putStrLn "[3/4] Registering WASI module into VM..."
  vm <- createVM Nothing Nothing
  resReg <- registerModuleFromImport vm wasiMod
  regOK <- case resReg of
    Left err -> fail $ "Failed to register WASI module into VM: " ++ show err
    Right () -> do
      putStrLn "      WASI module registered into VM successfully."
      deleteVM vm
      pure True

  -- 4. Scoped withWASIModule test
  putStrLn "[4/4] Testing scoped withWASIModule..."
  scopedOK <- withWASIModule ["scoped_app"] ["MODE=test"] [] $ \m -> do
    code <- getWASIExitCode m
    pure (code == 0 || code == 1 || code == 2) -- Valid exit code return
  unless scopedOK $ fail "Scoped withWASIModule verification failed!"
  putStrLn "      Scoped withWASIModule completed successfully."

  t1 <- getTime Monotonic
  let dur = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf ">>> WASI Lifecycle Suite completed in %.3f s\n\n" dur

  pure
    WASILifecycleMetrics
      { wlmInitialExitCode = exitCode1
      , wlmReinitExitCode = exitCode2
      , wlmScopedSuccess = scopedOK
      , wlmVMRegistrationOK = regOK
      , wlmDurationSec = dur
      }
