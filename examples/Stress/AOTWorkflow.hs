{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.AOTWorkflow
Description : Ahead-Of-Time (AOT) compilation and execution benchmark suite
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Tests the full AOT compilation pipeline using 'WasmEdge.Compiler':
  1. Compiling in-memory WebAssembly bytecode to native shared library
  2. Configuring optimization levels (O0 through O3)
  3. Loading native compiled object files into 'VM'
  4. Benchmarking execution speed of AOT native vs Interpreter
  5. Verifying 100% numerical parity between AOT and interpreted runs
-}
module Stress.AOTWorkflow
  ( runAOTWorkflowSuite
  , AOTMetrics (..)
  ) where

import Control.Exception (throwIO)
import Control.Monad (unless)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Text.Printf (printf)

import Stress.WasmBytecode (fibWasm)
import WasmEdge.Compiler (compileBytes, withCompiler)
import WasmEdge.Configure
  ( CompilerOptions (..)
  , defaultCompilerOptions
  , setCompilerOptions
  , withConfigure
  )
import WasmEdge.Types (OptimizationLevel (..), OutputFormat (..), WasmVal (..))
import WasmEdge.VM (runWasmBytes, runWasmFile, withVM)

-- | Metrics recorded during AOT compilation and execution benchmark
data AOTMetrics = AOTMetrics
  { aotCompileDurationSec :: !Double
  , aotInterpreterSec :: !Double
  , aotNativeSec :: !Double
  , aotSpeedupRatio :: !Double
  , aotNumericalParity :: !Bool
  }
  deriving stock (Show)

-- | Run the AOT compilation and execution suite.
runAOTWorkflowSuite :: IO AOTMetrics
runAOTWorkflowSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Ahead-Of-Time (AOT) Compilation & Speedup"
  putStrLn "============================================================"

  let n = 28 :: Int -- fib(28) = 317811
      expectedResult = 317811 :: Int

  withSystemTempDirectory "wasmedge_aot_stress" $ \tempDir -> do
    let aotPath = tempDir </> "fib_aot.so"

    -- 1. Compile fibWasm to native .so at OptO3
    putStrLn "--> [1/3] Compiling fibWasm to native shared library (Optimization Level: OptO3)..."
    tCompile0 <- getTime Monotonic
    compileRes <- withConfigure $ \cfg -> do
      setCompilerOptions
        cfg
        defaultCompilerOptions
          { compOptLevel = OptO3
          , compOutputFormat = OutputNativeSharedLibrary
          }
      withCompiler (Just cfg) $ \compiler ->
        compileBytes compiler fibWasm aotPath
    tCompile1 <- getTime Monotonic

    case compileRes of
      Left err -> throwIO (userError $ "AOT compilation failed: " ++ show err)
      Right () -> pure ()

    let compileSec = fromIntegral (toNanoSecs (diffTimeSpec tCompile1 tCompile0)) / 1e9 :: Double
    printf "    AOT compilation completed in %.3f s -> %s\n" compileSec aotPath

    -- 2. Execute on Interpreter
    putStrLn $ printf "--> [2/3] Executing fib(%d) on Interpreter..." n
    tInterp0 <- getTime Monotonic
    interpRes <- withVM Nothing Nothing $ \vm ->
      runWasmBytes vm fibWasm "fib" [WasmI32 (fromIntegral n)]
    tInterp1 <- getTime Monotonic

    interpVal <- case interpRes of
      Left err -> throwIO (userError $ "Interpreter failed: " ++ show err)
      Right [WasmI32 v] -> pure (fromIntegral v :: Int)
      Right other -> throwIO (userError $ "Unexpected return: " ++ show other)
    let interpSec = fromIntegral (toNanoSecs (diffTimeSpec tInterp1 tInterp0)) / 1e9 :: Double
    printf "    Interpreter returned: %d in %.4f s\n" interpVal interpSec

    -- 3. Execute on AOT Native
    putStrLn $ printf "--> [3/3] Executing fib(%d) on AOT Native object..." n
    tNative0 <- getTime Monotonic
    nativeRes <- withVM Nothing Nothing $ \vm ->
      runWasmFile vm aotPath "fib" [WasmI32 (fromIntegral n)]
    tNative1 <- getTime Monotonic

    nativeVal <- case nativeRes of
      Left err -> throwIO (userError $ "AOT Native failed: " ++ show err)
      Right [WasmI32 v] -> pure (fromIntegral v :: Int)
      Right other -> throwIO (userError $ "Unexpected return: " ++ show other)
    let nativeSec = fromIntegral (toNanoSecs (diffTimeSpec tNative1 tNative0)) / 1e9 :: Double
    printf "    AOT Native returned:  %d in %.4f s\n" nativeVal nativeSec

    -- Parity and Speedup
    let parity = (interpVal == expectedResult) && (nativeVal == expectedResult)
        speedup = if nativeSec > 0 then interpSec / nativeSec else 1.0

    putStrLn $ "    Numerical parity: " ++ if parity then "PASSED (identical)" else "FAILED"
    printf "    AOT Speedup: %.2fx faster than Interpreter\n\n" speedup

    unless parity $
      throwIO (userError "AOT vs Interpreter result mismatch!")

    pure $
      AOTMetrics
        { aotCompileDurationSec = compileSec
        , aotInterpreterSec = interpSec
        , aotNativeSec = nativeSec
        , aotSpeedupRatio = speedup
        , aotNumericalParity = parity
        }
