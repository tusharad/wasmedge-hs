{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.TableIndirect
Description : Stress testing WebAssembly Table instances, types, and indirect calls
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Exercises:
  * 'createTableType' / 'deleteTableType' / 'withTableType'
  * 'getTableTypeRefType' / 'getTableTypeLimit'
  * 'createTable' / 'deleteTable' / 'withTable'
  * 'getTableType' / 'getTableData' / 'setTableData'
  * 'getTableSize' / 'growTable'
  * Adding tables to 'ModuleBuilder' via 'builderAddTable'
  * Fault testing on boundary violations
-}
module Stress.TableIndirect
  ( runTableIndirectSuite
  , TableMetrics (..)
  ) where

import Control.Monad (unless)
import Data.Maybe (isJust)
import Data.Word (Word32)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import WasmEdge.Module (buildHostModule, builderAddTable, findTable, listTables)
import WasmEdge.Table
  ( createTable
  , createTableType
  , deleteTableType
  , disarmTable
  , getTableData
  , getTableSize
  , getTableType
  , getTableTypeLimit
  , getTableTypeRefType
  , growTable
  , setTableData
  , withTable
  , withTableType
  )
import WasmEdge.Types (Limit (..), ValType (..), WasmVal (..))

data TableMetrics = TableMetrics
  { tmInitialSize :: !Word32
  , tmGrownSize :: !Word32
  , tmTableTypeMatched :: !Bool
  , tmRefTypeMatched :: !Bool
  , tmBoundaryTrapFired :: !Bool
  , tmHostModuleBound :: !Bool
  , tmDurationSec :: !Double
  }
  deriving stock (Show)

runTableIndirectSuite :: IO TableMetrics
runTableIndirectSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Table Instances, Indirect Dispatch & Growth"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  -- 1. TableType creation & inspection
  putStrLn "[1/6] Creating TableType (FuncRef, min=10, max=100)..."
  let initialLimit = Limit {limitMin = 10, limitMax = Just 100, limitShared = False}
  tt <- createTableType FuncRef initialLimit

  refTy <- getTableTypeRefType tt
  lim <- getTableTypeLimit tt
  printf
    "      TableType refType: %s, min: %d, max: %s\n"
    (show refTy)
    (limitMin lim)
    (show (limitMax lim))
  unless (refTy == FuncRef && limitMin lim == 10 && limitMax lim == Just 100) $
    fail "TableType metadata does not match configured properties!"

  -- 2. Scoped TableType & withTable test
  putStrLn "[2/6] Verifying scoped withTableType & withTable lifecycle..."
  scopedSuccess <- withTableType ExternRef (Limit 5 Nothing False) $ \stt -> do
    sttRef <- getTableTypeRefType stt
    sttLim <- getTableTypeLimit stt
    pure (sttRef == ExternRef && limitMin sttLim == 5)
  unless scopedSuccess $ fail "scoped withTableType inspection failed!"

  withTableSuccess <- withTableType FuncRef (Limit 2 Nothing False) $ \tmpTT ->
    withTable tmpTT $ \tmpT -> do
      reflType <- getTableType tmpT
      reflRef <- getTableTypeRefType reflType
      pure (reflRef == FuncRef)
  unless withTableSuccess $ fail "scoped withTable lifecycle failed!"

  -- 3. Table creation & data access
  putStrLn "[3/6] Creating TableInstance and testing element read/write..."
  table <- createTable tt
  initSize <- getTableSize table
  printf "      Initial table size: %d\n" initSize
  unless (initSize == 10) $ fail "TableInstance initial size mismatch!"

  -- Read default reference at index 0 (should be null FuncRef)
  resData0 <- getTableData table 0
  case resData0 of
    Right (WasmFuncRef p) ->
      printf "      table[0] initial FuncRef: %s\n" (show p)
    other -> fail $ "Unexpected table[0] initial value: " ++ show other

  -- Set reference at index 3
  resSet <- setTableData table 3 (WasmFuncRef Nothing)
  case resSet of
    Left err -> fail $ "Failed to setTableData at index 3: " ++ show err
    Right () -> putStrLn "      setTableData(index=3, nullFuncRef) succeeded"

  -- 4. Dynamic table growth
  putStrLn "[4/6] Growing table by 25 elements..."
  resGrow <- growTable table 25
  case resGrow of
    Left err -> fail $ "growTable failed: " ++ show err
    Right () -> pure ()

  grownSize <- getTableSize table
  printf "      New table size after growth: %d (expected 35)\n" grownSize
  unless (grownSize == 35) $ fail "Table size after growTable mismatch!"

  -- 5. Out-of-bounds fault verification
  putStrLn "[5/6] Testing out-of-bounds access rejection..."
  resOOB <- getTableData table 100 -- index 100 is out of bounds (size=35)
  trapFired <- case resOOB of
    Left _err -> do
      putStrLn "      Out-of-bounds getTableData correctly rejected with error (VERIFIED)"
      pure True
    Right _ -> fail "Out-of-bounds getTableData should have failed but succeeded!"

  -- 6. Integrating Table into Host Module
  putStrLn "[6/6] Integrating TableInstance into ModuleBuilder..."
  hostMod <- buildHostModule "custom_dispatch_mod" $ \builder -> do
    builderAddTable builder "indirect_table" table
  disarmTable table

  modTables <- listTables hostMod
  printf "      Host module tables: %s\n" (show modTables)
  unless ("indirect_table" `elem` modTables) $
    fail "Table missing from host module exports!"

  mFoundTable <- findTable hostMod "indirect_table"
  unless (isJust mFoundTable) $
    fail "findTable failed on host module!"

  deleteTableType tt

  t1 <- getTime Monotonic
  let dur = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf ">>> Table Indirect Suite completed in %.3f s\n\n" dur

  pure
    TableMetrics
      { tmInitialSize = initSize
      , tmGrownSize = grownSize
      , tmTableTypeMatched = True
      , tmRefTypeMatched = refTy == FuncRef
      , tmBoundaryTrapFired = trapFired
      , tmHostModuleBound = True
      , tmDurationSec = dur
      }
