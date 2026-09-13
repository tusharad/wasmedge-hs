{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.BigMemory
Description : Stress testing large linear memory allocations and data transfers
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Tests multi-megabyte buffer allocations, dynamic memory growth ('memory.grow'),
host-to-guest and guest-to-host data transfers, SHA-256 integrity verification,
and memory isolation between concurrent VMs.
-}
module Stress.BigMemory
  ( runBigMemorySuite
  , BigMemoryMetrics (..)
  ) where

import Control.Concurrent.Async (concurrently)
import Control.Exception (throwIO)
import Control.Monad (unless)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.Text (Text)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import Stress.WasmBytecode (memoryOpsWasm)
import WasmEdge.Memory
  ( createMemory
  , createMemoryType
  , getMemoryData
  , getMemoryPageSize
  , growMemoryPages
  , setMemoryData
  )
import WasmEdge.Module (findMemory)
import WasmEdge.Store (findModule)
import WasmEdge.Types (Limit (..), WasmVal (..))
import WasmEdge.VM

-- | Metrics recorded during the big memory stress test
data BigMemoryMetrics = BigMemoryMetrics
  { bmmInitialPages :: !Int
  , bmmGrownPages :: !Int
  , bmmTransferredMB :: !Double
  , bmmDurationSec :: !Double
  , bmmThroughputMBps :: !Double
  , bmmChecksumValid :: !Bool
  }
  deriving stock (Show)

-- | Run the comprehensive Big Memory stress suite.
runBigMemorySuite :: IO BigMemoryMetrics
runBigMemorySuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Big Memory (Multi-MB, Grow, SHA256, Isolation)"
  putStrLn "============================================================"

  start <- getTime Monotonic

  -- 1. Test standalone MemoryInstance creation and dynamic growth
  putStrLn "--> [1/4] Testing standalone MemoryInstance (grow to 32MB / 512 pages)..."
  mt <- createMemoryType (Limit 1 (Just 1024) False)
  mem <- createMemory mt
  initialPages <- getMemoryPageSize mem
  putStrLn $ "    Initial page size: " ++ show initialPages ++ " pages (64 KiB)"

  -- Grow by 511 pages (to 512 pages = 32MB)
  growRes <- growMemoryPages mem 511
  case growRes of
    Left err -> throwIO (userError $ "Failed to grow memory: " ++ show err)
    Right () -> pure ()
  newPages <- getMemoryPageSize mem
  putStrLn $ "    New page size: " ++ show newPages ++ " pages (32 MiB)"

  -- 2. Test writing 8MB from Haskell into MemoryInstance and reading it back with SHA-256
  putStrLn "--> [2/4] Streaming 8MB from host into memory, validating SHA-256..."
  let eightMB = 8 * 1024 * 1024
      chunk = BS.replicate eightMB 0x7E
      expectedHash = SHA256.hash chunk

  writeRes <- setMemoryData mem 0 chunk
  case writeRes of
    Left err -> throwIO (userError $ "Failed to write memory: " ++ show err)
    Right () -> pure ()

  readRes <- getMemoryData mem 0 (fromIntegral eightMB)
  readBytes <- case readRes of
    Left err -> throwIO (userError $ "Failed to read memory: " ++ show err)
    Right bs -> pure bs

  let actualHash = SHA256.hash readBytes
      hashMatches = expectedHash == actualHash
  putStrLn $ "    SHA-256 verification: " ++ if hashMatches then "PASSED" else "FAILED"
  unless hashMatches $
    throwIO (userError "SHA-256 hash mismatch on 8MB buffer transfer!")

  -- 3. Test running WASM guest with dynamic memory.grow and memory inspection via VM
  putStrLn "--> [3/4] Registering memoryOpsWasm in VM, growing memory from inside guest..."
  (grownPagesCount, guestHashOk) <- withVM Nothing Nothing $ \vm -> do
    -- Register as named module so we can query it from Store
    let modName = "mem_test" :: Text
    regRes <- registerModuleFromBytes vm modName memoryOpsWasm
    case regRes of
      Left err -> throwIO (userError $ "Failed to register module: " ++ show err)
      Right () -> pure ()

    -- Call memory_size (should be 1 page)
    Right [WasmI32 initPages] <- executeRegistered vm modName "memory_size" []
    putStrLn $ "    Guest reports memory_size = " ++ show initPages ++ " pages"

    -- Call grow_memory 255 (to 256 pages = 16MB)
    Right [WasmI32 prevPages] <- executeRegistered vm modName "grow_memory" [WasmI32 255]
    putStrLn $ "    Guest memory.grow returned previous size = " ++ show prevPages

    -- Call memory_size (now 256)
    Right [WasmI32 currentPages] <- executeRegistered vm modName "memory_size" []
    putStrLn $ "    Guest reports new memory_size = " ++ show currentPages ++ " pages (16 MiB)"

    -- Execute fill_pattern in guest: offset=0, len=1,048,576 (1MB), val=0x42 ('B')
    let oneMB = 1024 * 1024
    Right [WasmI32 guestSum] <-
      executeRegistered vm modName "fill_pattern" [WasmI32 0, WasmI32 (fromIntegral oneMB), WasmI32 0x42]
    let expectedSum = oneMB * 0x42 :: Int
    putStrLn $
      "    Guest fill_pattern sum: " ++ show guestSum ++ " (expected " ++ show expectedSum ++ ")"

    -- Retrieve MemoryInstance from VM Store and verify bytes directly from host
    store <- getStore vm
    mMod <- findModule store modName
    case mMod of
      Nothing -> throwIO (userError "Module not found in store!")
      Just mi -> do
        mGuestMem <- findMemory mi "memory"
        case mGuestMem of
          Nothing -> throwIO (userError "Exported 'memory' not found on module instance!")
          Just guestMem -> do
            Right hostReadBS <- getMemoryData guestMem 0 (fromIntegral oneMB)
            let hostHash = SHA256.hash hostReadBS
                expectedHostBS = BS.replicate oneMB 0x42
                guestExpectedHash = SHA256.hash expectedHostBS
            pure (fromIntegral currentPages, hostHash == guestExpectedHash)

  -- 4. Test Memory Isolation between concurrent VMs
  putStrLn "--> [4/4] Testing memory isolation between 2 concurrent VMs..."
  let twoMB = 2 * 1024 * 1024
      patternA = BS.replicate twoMB 0xAA
      patternB = BS.replicate twoMB 0xBB

  (isoA, isoB) <-
    concurrently
      ( withVM Nothing Nothing $ \vmA -> do
          _ <- registerModuleFromBytes vmA "modA" memoryOpsWasm
          _ <- executeRegistered vmA "modA" "grow_memory" [WasmI32 63] -- 64 pages = 4MB
          storeA <- getStore vmA
          Just miA <- findModule storeA "modA"
          Just memA <- findMemory miA "memory"
          _ <- setMemoryData memA 0 patternA
          Right readA <- getMemoryData memA 0 (fromIntegral twoMB)
          pure (readA == patternA)
      )
      ( withVM Nothing Nothing $ \vmB -> do
          _ <- registerModuleFromBytes vmB "modB" memoryOpsWasm
          _ <- executeRegistered vmB "modB" "grow_memory" [WasmI32 63] -- 64 pages = 4MB
          storeB <- getStore vmB
          Just miB <- findModule storeB "modB"
          Just memB <- findMemory miB "memory"
          _ <- setMemoryData memB 0 patternB
          Right readB <- getMemoryData memB 0 (fromIntegral twoMB)
          pure (readB == patternB)
      )

  if isoA && isoB
    then putStrLn "    Memory isolation test: PASSED (zero cross-talk)"
    else throwIO (userError "Memory isolation test FAILED!")

  end <- getTime Monotonic
  let diffNanos = toNanoSecs (diffTimeSpec end start)
      durSec = fromIntegral diffNanos / 1e9 :: Double
      totalTransferredMB = 8.0 + 1.0 + 4.0 -- 8MB + 1MB + 4MB
      throughput = totalTransferredMB / durSec

  printf "==> Big Memory Test PASSED in %.3f s (%.2f MB/s throughput)\n\n" durSec throughput
  pure $
    BigMemoryMetrics
      { bmmInitialPages = fromIntegral initialPages
      , bmmGrownPages = grownPagesCount
      , bmmTransferredMB = totalTransferredMB
      , bmmDurationSec = durSec
      , bmmThroughputMBps = throughput
      , bmmChecksumValid = hashMatches && guestHashOk && isoA && isoB
      }
