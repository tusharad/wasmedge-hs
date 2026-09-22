{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Stress.StoreReflection
Description : Comprehensive Store and ModuleInstance introspection & reflection suite
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Exercises:
  * 'listModules' / 'findModule' on 'Store'
  * 'getModuleName' on 'ModuleInstance'
  * 'listFunctions' / 'findFunction'
  * 'listMemories' / 'findMemory'
  * 'listTables' / 'findTable'
  * 'listGlobals' / 'findGlobal'
  * 'listTags' / 'findTag'
-}
module Stress.StoreReflection
  ( runStoreReflectionSuite
  , StoreReflectionMetrics (..)
  ) where

import Control.Monad (unless)
import Data.Int (Int32)
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import WasmEdge.Executor (createExecutor, deleteExecutor, registerImportModule)
import WasmEdge.Global (createGlobal, createGlobalType, deleteGlobalType)
import WasmEdge.Memory (createMemory, createMemoryType, deleteMemoryType)
import WasmEdge.Module
  ( buildHostModule
  , builderAddGlobal
  , builderAddHostFunc
  , builderAddMemory
  , builderAddTable
  , findFunction
  , findGlobal
  , findMemory
  , findTable
  , findTag
  , getModuleName
  , listFunctions
  , listGlobals
  , listMemories
  , listTables
  , listTags
  )
import WasmEdge.Store (createStore, deleteStore, findModule, listModules)
import WasmEdge.Table (createTable, createTableType, deleteTableType)
import WasmEdge.Types (Limit (..), Mutability (..), ValType (..), WasmVal (..))

data StoreReflectionMetrics = StoreReflectionMetrics
  { srmModulesCount :: !Int
  , srmFunctionsReflected :: ![Text]
  , srmMemoriesReflected :: ![Text]
  , srmTablesReflected :: ![Text]
  , srmGlobalsReflected :: ![Text]
  , srmTagsReflected :: ![Text]
  , srmDurationSec :: !Double
  }
  deriving stock (Show)

runStoreReflectionSuite :: IO StoreReflectionMetrics
runStoreReflectionSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Store & Module Instance Introspection"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  -- 1. Create a Store and Executor
  putStrLn "[1/5] Creating runtime Store & Executor..."
  store <- createStore
  executor <- createExecutor Nothing Nothing

  -- 2. Build a rich host module exporting function, memory, table, and global
  putStrLn "[2/5] Constructing multi-export HostModule..."
  memType <- createMemoryType (Limit 2 (Just 10) False)
  memInst <- createMemory memType
  deleteMemoryType memType

  tabType <- createTableType FuncRefT (Limit 5 (Just 20) False)
  tabInst <- createTable tabType
  deleteTableType tabType

  globType <- createGlobalType I32 Var
  globInst <- createGlobal globType (WasmI32 1001)
  deleteGlobalType globType

  hostMod <- buildHostModule "reflection_catalog_mod" $ \builder -> do
    builderAddHostFunc builder "catalog_version" (pure 42 :: IO Int32)
    builderAddHostFunc builder "catalog_ping" (\(x :: Int32) -> pure (x + 1) :: IO Int32)
    builderAddMemory builder "catalog_mem" memInst
    builderAddTable builder "catalog_tab" tabInst
    builderAddGlobal builder "catalog_counter" globInst

  -- 3. Register module into store
  putStrLn "[3/5] Registering HostModule into Store..."
  resReg <- registerImportModule executor store hostMod
  case resReg of
    Left err -> fail $ "Failed to register host module into store: " ++ show err
    Right () -> putStrLn "      Registered successfully."

  -- 4. Store reflection: listModules and findModule
  putStrLn "[4/5] Reflecting on registered modules in Store..."
  allMods <- listModules store
  printf "      Registered modules in store: %s\n" (show allMods)
  unless ("reflection_catalog_mod" `elem` allMods) $
    fail "Module 'reflection_catalog_mod' not found in store listModules!"

  mFoundMod <- findModule store "reflection_catalog_mod"
  foundMod <- case mFoundMod of
    Nothing -> fail "findModule failed to locate 'reflection_catalog_mod'!"
    Just m -> pure m

  modName <- getModuleName foundMod
  printf "      Module name confirmed: %s\n" (T.unpack modName)

  -- 5. Module reflection: list and find each exported component
  putStrLn "[5/5] Reflecting on exports: functions, memories, tables, globals, tags..."
  funcs <- listFunctions foundMod
  printf "      Exported functions: %s\n" (show funcs)
  unless ("catalog_version" `elem` funcs && "catalog_ping" `elem` funcs) $
    fail "Exported functions reflection incomplete!"
  mFn <- findFunction foundMod "catalog_version"
  unless (isJust mFn) $ fail "findFunction 'catalog_version' failed!"

  mems <- listMemories foundMod
  printf "      Exported memories: %s\n" (show mems)
  unless ("catalog_mem" `elem` mems) $
    fail "Exported memories reflection incomplete!"
  mMem <- findMemory foundMod "catalog_mem"
  unless (isJust mMem) $ fail "findMemory 'catalog_mem' failed!"

  tabs <- listTables foundMod
  printf "      Exported tables: %s\n" (show tabs)
  unless ("catalog_tab" `elem` tabs) $
    fail "Exported tables reflection incomplete!"
  mTab <- findTable foundMod "catalog_tab"
  unless (isJust mTab) $ fail "findTable 'catalog_tab' failed!"

  globs <- listGlobals foundMod
  printf "      Exported globals: %s\n" (show globs)
  unless ("catalog_counter" `elem` globs) $
    fail "Exported globals reflection incomplete!"
  mGlob <- findGlobal foundMod "catalog_counter"
  unless (isJust mGlob) $ fail "findGlobal 'catalog_counter' failed!"

  tags <- listTags foundMod
  printf "      Exported tags: %s\n" (show tags)
  mTag <- findTag foundMod "dummy_tag"
  unless (isNothing mTag) $ fail "findTag on dummy should be Nothing!"

  deleteStore store
  deleteExecutor executor

  t1 <- getTime Monotonic
  let dur = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf ">>> Store Reflection Suite completed in %.3f s\n\n" dur

  pure
    StoreReflectionMetrics
      { srmModulesCount = length allMods
      , srmFunctionsReflected = funcs
      , srmMemoriesReflected = mems
      , srmTablesReflected = tabs
      , srmGlobalsReflected = globs
      , srmTagsReflected = tags
      , srmDurationSec = dur
      }
