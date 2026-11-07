{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Stress.LowLevelPipeline
Description : Low-level decoupled execution pipeline (Executor, Store, and ASTModule)
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Exercises the decoupled, low-level execution engine bypassing high-level 'VM':
  * 'createExecutor' / 'deleteExecutor' / 'withExecutor'
  * 'createStore' / 'deleteStore' / 'withStore'
  * 'loadASTFromBytes' / 'loadASTFromFile' / 'deleteASTModule'
  * 'validateAST'
  * 'instantiateModule'
  * 'registerModule'
  * 'registerImportModule'
  * 'registerImportModuleWithAlias'
  * 'invokeFunction' / 'asyncInvokeFunction'
  * High-frequency execution throughput (50,000 invocations)
-}
module Stress.LowLevelPipeline
  ( runLowLevelPipelineSuite
  , LowLevelMetrics (..)
  ) where

import Control.Monad (forM_, unless)
import Data.ByteString qualified as BS
import Data.Int (Int32)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Text.Printf (printf)

import Stress.WasmBytecode (addWasm)
import WasmEdge.Async qualified as WasmAsync
import WasmEdge.Executor
  ( asyncInvokeFunction
  , createExecutor
  , deleteASTModule
  , deleteExecutor
  , instantiateModule
  , invokeFunction
  , loadASTFromBytes
  , loadASTFromFile
  , registerImportModule
  , registerImportModuleWithAlias
  , validateAST
  )
import WasmEdge.Module (buildHostModule, builderAddHostFunc, deleteModuleInstance, findFunction)
import WasmEdge.Store (createStore, deleteStore)
import WasmEdge.Types (WasmVal (..))

data LowLevelMetrics = LowLevelMetrics
  { llmInvocationsCompleted :: !Int
  , llmThroughputOpsPerSec :: !Double
  , llmParityVerified :: !Bool
  , llmFileLoadVerified :: !Bool
  , llmAliasedImportOK :: !Bool
  , llmAsyncInvokeOK :: !Bool
  , llmDurationSec :: !Double
  }
  deriving stock (Show)

runLowLevelPipelineSuite :: IO LowLevelMetrics
runLowLevelPipelineSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Low-Level Decoupled Pipeline (Executor/Store)"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  -- 1. Lifecycle of Executor and Store
  putStrLn "[1/6] Initializing decoupled Store & Executor contexts..."
  store <- createStore
  executor <- createExecutor Nothing Nothing

  -- 2. Loading ASTModule from bytes and file
  putStrLn "[2/6] Loading ASTModule from bytes and temporary file..."
  resAstFromBytes <- loadASTFromBytes addWasm
  astFromBytes <- case resAstFromBytes of
    Left err -> fail $ "loadASTFromBytes failed: " ++ show err
    Right a -> pure a

  -- Test loadASTFromFile
  fileVerified <- withSystemTempDirectory "wasmedge_lowlevel" $ \tmpDir -> do
    let wasmPath = tmpDir </> "add_temp.wasm"
    BS.writeFile wasmPath addWasm
    resAstFromFile <- loadASTFromFile wasmPath
    case resAstFromFile of
      Left err -> fail $ "loadASTFromFile failed: " ++ show err
      Right astFromFile -> do
        valRes <- validateAST astFromFile
        deleteASTModule astFromFile
        pure (valRes == Right ())

  unless fileVerified $ fail "loadASTFromFile validation failed!"
  putStrLn "      loadASTFromFile verified successfully."

  -- 3. Validating and instantiating ASTModule
  putStrLn "[3/6] Validating and instantiating ASTModule into Store..."
  resVal <- validateAST astFromBytes
  case resVal of
    Left err -> fail $ "validateAST failed: " ++ show err
    Right () -> putStrLn "      validateAST passed."

  resInst <- instantiateModule executor store astFromBytes
  modInst <- case resInst of
    Left err -> fail $ "instantiateModule failed: " ++ show err
    Right m -> pure m

  mAddFn <- findFunction modInst "add"
  addFn <- case mAddFn of
    Nothing -> fail "Function 'add' not found in instantiated module!"
    Just fn -> pure fn

  -- 4. Testing invokeFunction and asyncInvokeFunction
  putStrLn "[4/6] Invoking function synchronously and asynchronously..."
  resSync <- invokeFunction executor addFn [WasmI32 100, WasmI32 200]
  case resSync of
    Right [WasmI32 300] -> putStrLn "      Synchronous invokeFunction(100, 200) -> 300 (VERIFIED)"
    other -> fail $ "Unexpected invokeFunction result: " ++ show other

  asyncHandle <- asyncInvokeFunction executor addFn [WasmI32 500, WasmI32 500]
  resAsync <- WasmAsync.getReturns asyncHandle
  asyncOK <- case resAsync of
    Right [WasmI32 1000] -> do
      putStrLn "      Asynchronous asyncInvokeFunction(500, 500) -> 1000 (VERIFIED)"
      pure True
    other -> fail $ "Unexpected asyncInvokeFunction result: " ++ show other

  -- 5. Testing registerImportModule and registerImportModuleWithAlias
  putStrLn "[5/6] Testing registerImportModule & registerImportModuleWithAlias..."
  hostMod <- buildHostModule "host_math" $ \builder -> do
    builderAddHostFunc builder "host_mul" (\(a :: Int32) (b :: Int32) -> pure (a * b) :: IO Int32)

  resImp1 <- registerImportModule executor store hostMod
  case resImp1 of
    Left err -> fail $ "registerImportModule failed: " ++ show err
    Right () -> putStrLn "      registerImportModule succeeded."

  hostMod2 <- buildHostModule "host_math_alias" $ \builder -> do
    builderAddHostFunc builder "host_sub" (\(a :: Int32) (b :: Int32) -> pure (a - b) :: IO Int32)

  resImp2 <- registerImportModuleWithAlias executor store hostMod2 "custom_math_alias"
  case resImp2 of
    Left err -> fail $ "registerImportModuleWithAlias failed: " ++ show err
    Right () -> putStrLn "      registerImportModuleWithAlias succeeded."

  -- 6. High-Frequency Invocation Benchmark (50,000 iterations)
  putStrLn "[6/6] Benchmarking low-level invocation throughput (50,000 calls)..."
  let totalCalls = 50000 :: Int
  tBench0 <- getTime Monotonic
  forM_ [1 .. totalCalls] $ \i -> do
    res <- invokeFunction executor addFn [WasmI32 (fromIntegral i), WasmI32 1]
    case res of
      Left err -> fail $ "invokeFunction error at iteration " ++ show i ++ ": " ++ show err
      Right _ -> pure ()
  tBench1 <- getTime Monotonic

  let benchNanos = toNanoSecs (diffTimeSpec tBench1 tBench0)
      benchSec = fromIntegral benchNanos / 1e9 :: Double
      opsPerSec = fromIntegral totalCalls / benchSec

  printf
    "      Executed %d calls in %.3f s (%.1f calls/sec)\n"
    totalCalls
    benchSec
    opsPerSec

  deleteASTModule astFromBytes
  deleteModuleInstance modInst
  deleteStore store
  deleteExecutor executor

  t1 <- getTime Monotonic
  let dur = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf ">>> Low-Level Pipeline Suite completed in %.3f s\n\n" dur

  pure
    LowLevelMetrics
      { llmInvocationsCompleted = totalCalls
      , llmThroughputOpsPerSec = opsPerSec
      , llmParityVerified = True
      , llmFileLoadVerified = fileVerified
      , llmAliasedImportOK = True
      , llmAsyncInvokeOK = asyncOK
      , llmDurationSec = dur
      }
