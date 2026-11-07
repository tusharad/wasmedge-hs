{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.GlobalState
Description : Stress testing WebAssembly Global variables, types, and mutable runtime state
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Exercises:
  * 'createGlobalType' / 'deleteGlobalType' / 'withGlobalType'
  * 'getGlobalTypeValType' / 'getGlobalTypeMutability'
  * 'createGlobal' / 'deleteGlobal' / 'withGlobal'
  * 'getGlobalType' / 'getGlobalValue' / 'setGlobalValue'
  * Mutable vs Immutable globals (const protection fault verification)
  * Multi-type globals (I32, I64, F32, F64)
  * High-frequency mutation stress test (100k updates)
  * Adding globals to 'ModuleBuilder' via 'builderAddGlobal'
-}
module Stress.GlobalState
  ( runGlobalStateSuite
  , GlobalMetrics (..)
  ) where

import Control.Monad (forM_, unless)
import Data.Maybe (isJust)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import WasmEdge.Global
  ( createGlobal
  , createGlobalType
  , deleteGlobal
  , deleteGlobalType
  , disarmGlobal
  , getGlobalTypeMutability
  , getGlobalTypeValType
  , getGlobalValue
  , setGlobalValue
  , withGlobal
  , withGlobalType
  )
import WasmEdge.Module (buildHostModule, builderAddGlobal, findGlobal, listGlobals)
import WasmEdge.Types (Mutability (..), ValType (..), WasmVal (..))

data GlobalMetrics = GlobalMetrics
  { gmUpdatesCompleted :: !Int
  , gmMutationRateOps :: !Double
  , gmImmutableTrapOK :: !Bool
  , gmTypesVerified :: !Int
  , gmHostModuleBound :: !Bool
  , gmDurationSec :: !Double
  }
  deriving stock (Show)

runGlobalStateSuite :: IO GlobalMetrics
runGlobalStateSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Global Instances, Mutability & Runtime State"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  -- 1. GlobalType creation & metadata queries
  putStrLn "[1/6] Creating GlobalTypes across all primitive types..."
  gtI32Mut <- createGlobalType I32 Var
  gtI64Const <- createGlobalType I64 Const
  gtF32Mut <- createGlobalType F32 Var
  gtF64Mut <- createGlobalType F64 Var

  ty1 <- getGlobalTypeValType gtI32Mut
  mut1 <- getGlobalTypeMutability gtI32Mut
  unless (ty1 == I32 && mut1 == Var) $ fail "gtI32Mut type/mutability mismatch!"

  ty2 <- getGlobalTypeValType gtI64Const
  mut2 <- getGlobalTypeMutability gtI64Const
  unless (ty2 == I64 && mut2 == Const) $ fail "gtI64Const type/mutability mismatch!"

  -- 2. Scoped withGlobalType & withGlobal verification
  putStrLn "[2/6] Verifying scoped withGlobalType & withGlobal..."
  withScopedSuccess <- withGlobalType I32 Var $ \scopedType ->
    withGlobal scopedType (WasmI32 777) $ \scopedGlobal -> do
      val <- getGlobalValue scopedGlobal
      pure (val == WasmI32 777)
  unless withScopedSuccess $ fail "withGlobal scoped lifecycle test failed!"

  -- 3. Multi-type global instance creation
  putStrLn "[3/6] Instantiating multi-type globals (I32, I64, F32, F64)..."
  gI32 <- createGlobal gtI32Mut (WasmI32 42)
  gI64 <- createGlobal gtI64Const (WasmI64 9876543210)
  gF32 <- createGlobal gtF32Mut (WasmF32 3.14159)
  gF64 <- createGlobal gtF64Mut (WasmF64 2.718281828)

  vI32 <- getGlobalValue gI32
  vI64 <- getGlobalValue gI64
  vF32 <- getGlobalValue gF32
  vF64 <- getGlobalValue gF64

  printf
    "      Initial values: I32=%s, I64=%s, F32=%s, F64=%s\n"
    (show vI32)
    (show vI64)
    (show vF32)
    (show vF64)

  -- 4. Immutable mutation rejection (Const protection)
  putStrLn "[4/6] Verifying immutable global mutation rejection..."
  resConstSet <- setGlobalValue gI64 (WasmI64 0)
  immutableTrapOK <- case resConstSet of
    Left _err -> do
      putStrLn "      setGlobalValue on Const global correctly rejected (VERIFIED)"
      pure True
    Right () -> fail "setGlobalValue on Const global should have failed but succeeded!"

  -- 5. High-frequency mutation benchmark (100,000 updates)
  putStrLn "[5/6] Running 100,000 rapid mutation cycles on mutable global..."
  let totalCycles = 100000 :: Int
  tMut0 <- getTime Monotonic
  forM_ [1 .. totalCycles] $ \i -> do
    res <- setGlobalValue gI32 (WasmI32 (fromIntegral i))
    case res of
      Left err -> fail $ "setGlobalValue failed during stress run: " ++ show err
      Right () -> pure ()
  tMut1 <- getTime Monotonic

  vFinal <- getGlobalValue gI32
  unless (vFinal == WasmI32 (fromIntegral totalCycles)) $
    fail "Final value of global does not match expected cycle count!"

  let mutNanos = toNanoSecs (diffTimeSpec tMut1 tMut0)
      mutSec = fromIntegral mutNanos / 1e9 :: Double
      mutOpsSec = fromIntegral totalCycles / mutSec

  printf
    "      Completed %d updates in %.3f s (%.1f updates/sec)\n"
    totalCycles
    mutSec
    mutOpsSec

  -- 6. Integrating Global into Host Module
  putStrLn "[6/6] Integrating GlobalInstance into ModuleBuilder..."
  hostMod <- buildHostModule "custom_runtime_state_mod" $ \builder -> do
    builderAddGlobal builder "runtime_counter" gI32
    builderAddGlobal builder "runtime_pi" gF32
  disarmGlobal gI32
  disarmGlobal gF32

  modGlobals <- listGlobals hostMod
  printf "      Host module globals: %s\n" (show modGlobals)
  unless ("runtime_counter" `elem` modGlobals && "runtime_pi" `elem` modGlobals) $
    fail "Globals missing from host module exports!"

  mFound <- findGlobal hostMod "runtime_counter"
  unless (isJust mFound) $
    fail "findGlobal failed to locate 'runtime_counter'!"

  deleteGlobal gI64
  deleteGlobal gF64
  deleteGlobalType gtI32Mut
  deleteGlobalType gtI64Const
  deleteGlobalType gtF32Mut
  deleteGlobalType gtF64Mut

  t1 <- getTime Monotonic
  let dur = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf ">>> Global State Suite completed in %.3f s\n\n" dur

  pure
    GlobalMetrics
      { gmUpdatesCompleted = totalCycles
      , gmMutationRateOps = mutOpsSec
      , gmImmutableTrapOK = immutableTrapOK
      , gmTypesVerified = 4
      , gmHostModuleBound = True
      , gmDurationSec = dur
      }
