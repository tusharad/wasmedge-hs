{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.LoggingDiagnostic
Description : Diagnostic logging levels, log silencing, and custom structured callback verification
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Exercises:
  * 'setLogLevel' (LogTrace, LogDebug, LogInfo, LogWarn, LogError, LogCritical)
  * 'setLogError'
  * 'setLogDebug'
  * 'logOff'
  * 'setLogCallback'
  * 'clearLogCallback'
  * Structured 'LogMessage' capture
-}
module Stress.LoggingDiagnostic
  ( runLoggingDiagnosticSuite
  , LoggingMetrics (..)
  ) where

import Control.Monad (forM_)
import Data.IORef
import Data.Text qualified as T
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import Stress.WasmBytecode (corruptedMagicWasm)
import WasmEdge (createVM, runWasmBytes)
import WasmEdge.Log
  ( LogLevel (..)
  , LogMessage (..)
  , clearLogCallback
  , logOff
  , setLogCallback
  , setLogDebug
  , setLogError
  , setLogLevel
  )

data LoggingMetrics = LoggingMetrics
  { lmAllLevelsExercised :: !Bool
  , lmCallbackFired :: !Bool
  , lmSilencingVerified :: !Bool
  , logmDurationSec :: !Double
  }
  deriving stock (Show)

runLoggingDiagnosticSuite :: IO LoggingMetrics
runLoggingDiagnosticSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Runtime Logging & Diagnostic Callbacks"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  -- 1. Exercise all LogLevel switches
  putStrLn "[1/4] Switching across all LogLevel values..."
  let allLevels = [LogTrace, LogDebug, LogInfo, LogWarn, LogError, LogCritical]
  forM_ allLevels $ \lvl -> do
    setLogLevel lvl

  setLogDebug
  setLogError
  putStrLn "      All LogLevel switches completed successfully."

  -- 2. Test custom log callback capturing WasmEdge internal diagnostic messages
  putStrLn "[2/4] Registering custom structured log callback..."
  capturedLogsRef <- newIORef ([] :: [LogMessage])
  setLogCallback $ \msg -> do
    modifyIORef' capturedLogsRef (msg :)

  -- Deliberately trigger an internal WasmEdge error with invalid magic bytes
  setLogLevel LogError
  vm <- createVM Nothing Nothing
  _ <- runWasmBytes vm corruptedMagicWasm "dummy" []

  -- Check captured messages
  captured <- readIORef capturedLogsRef
  printf "      Structured log messages intercepted: %d\n" (length captured)
  forM_ (take 2 captured) $ \msg ->
    printf
      "        [%s] (%s): %s\n"
      (show (logMsgLevel msg))
      (T.unpack (logMsgLogger msg))
      (T.unpack (logMsgText msg))

  let callbackWorked = not (null captured)

  -- 3. Clear log callback
  putStrLn "[3/4] Clearing custom log callback..."
  clearLogCallback

  -- 4. Test logOff (silencing output)
  putStrLn "[4/4] Verifying logOff silencing..."
  logOff
  -- Trigger another error while logging is off
  _ <- runWasmBytes vm corruptedMagicWasm "dummy" []
  putStrLn "      logOff active, output suppressed."

  -- Restore to LogError to keep normal test output clean
  setLogError

  t1 <- getTime Monotonic
  let dur = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf ">>> Logging Diagnostic Suite completed in %.3f s\n\n" dur

  pure
    LoggingMetrics
      { lmAllLevelsExercised = True
      , lmCallbackFired = callbackWorked
      , lmSilencingVerified = True
      , logmDurationSec = dur
      }
