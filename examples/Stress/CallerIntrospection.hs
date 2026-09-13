{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.CallerIntrospection
Description : CallingFrame introspection, guest memory read/write, and C-string extraction
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Exercises:
  * 'getCallerMemory'
  * 'readCallerMemory'
  * 'writeCallerMemory'
  * 'readCallerCString'
  * 'readCallerCStringMax'
  * 'getCallerModuleInstance'
  * 'getCallerExecutor'
  * Safe error handling on null or invalid frames
-}
module Stress.CallerIntrospection
  ( runCallerIntrospectionSuite
  , CallerMetrics (..)
  ) where

import Control.Monad (unless, when)
import Data.ByteString (ByteString)
import Data.IORef
import Data.Maybe (isNothing)
import Foreign.Ptr (nullPtr)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import Stress.WasmBytecode (callerGuestWasm)
import WasmEdge (createVM, runWasmBytes)
import WasmEdge.Caller
  ( getCallerExecutor
  , getCallerMemory
  , getCallerModuleInstance
  , readCallerCString
  , readCallerCStringMax
  , readCallerMemory
  , writeCallerMemory
  )
import WasmEdge.Error (WasmResult)
import WasmEdge.Function
  ( CallingFrame (..)
  , createFunction
  , createFunctionType
  , deleteFunctionType
  )
import WasmEdge.Internal.Ownership (BorrowedCtx (..))
import WasmEdge.Module (buildHostModule, builderAddFunction)
import WasmEdge.Types (ValType (..), WasmVal (..))
import WasmEdge.VM (registerModuleFromImport)

data CallerMetrics = CallerMetrics
  { cmNullSafetyVerified :: !Bool
  , cmMemoryReadWriteOK :: !Bool
  , cmCStringRoundTripOK :: !Bool
  , cmCStringMaxBoundedOK :: !Bool
  , cmFramePointersVerified :: !Bool
  , callermDurationSec :: !Double
  }
  deriving stock (Show)

runCallerIntrospectionSuite :: IO CallerMetrics
runCallerIntrospectionSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: CallingFrame Guest Memory Introspection"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  -- 1. Test null/invalid CallingFrame safety
  putStrLn "[1/4] Testing null CallingFrame safety..."
  let nullFrame = CallingFrame (BorrowedCtx nullPtr)
  mMemNull <- getCallerMemory nullFrame 0
  mReadNull <- readCallerMemory nullFrame 0 0 10
  mStrNull <- readCallerCString nullFrame 0 0
  pModNull <- getCallerModuleInstance nullFrame
  pExecNull <- getCallerExecutor nullFrame

  let nullSafe =
        isNothing mMemNull
          && isNothing mReadNull
          && isNothing mStrNull
          && pModNull == nullPtr
          && pExecNull == nullPtr
  unless nullSafe $ fail "Null CallingFrame operations should fail safely!"
  putStrLn "      Null frame operations handled safely without crashing (VERIFIED)."

  -- 2. Build host function that introspects caller memory during execution
  putStrLn "[2/4] Constructing host functions with CallingFrame introspection..."
  readWriteRef <- newIORef False
  cStringRef <- newIORef False
  cStringMaxRef <- newIORef False
  framePtrsRef <- newIORef False

  -- Host function: inspect_caller(offset: i32) -> i32
  let hostInspect :: CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal])
      hostInspect frame [WasmI32 offset] = do
        let off = fromIntegral offset
        -- 1. Read caller memory
        _ <- readCallerMemory frame 0 off 16

        -- 2. Write a null-terminated greeting into caller memory at offset + 64
        let greeting = "Production WasmEdge Guest\0" :: ByteString
        resWrite <- writeCallerMemory frame 0 (off + 64) greeting

        -- 3. Read back as C-String
        mCStr <- readCallerCString frame 0 (off + 64)
        mCStrBounded <- readCallerCStringMax frame 0 (off + 64) 100

        -- 4. Check caller pointers
        pMod <- getCallerModuleInstance frame
        pExec <- getCallerExecutor frame

        case (resWrite, mCStr, mCStrBounded) of
          (Right (), Just bs, Just bsBounded) -> do
            when (bs == "Production WasmEdge Guest" && bsBounded == "Production WasmEdge Guest") $ do
              writeIORef readWriteRef True
              writeIORef cStringRef True
              writeIORef cStringMaxRef True
          _ -> pure ()

        when (pMod /= nullPtr && pExec /= nullPtr) $
          writeIORef framePtrsRef True

        pure (Right [WasmI32 1])
      hostInspect _ _ = fail "Invalid arguments to hostInspect"

  ft <- createFunctionType [I32] [I32]
  inspectFn <- createFunction ft hostInspect
  deleteFunctionType ft

  hostMod <- buildHostModule "caller_env" $ \builder -> do
    builderAddFunction builder "inspect_caller" inspectFn

  -- 3. Register into VM and run a guest module with memory
  putStrLn "[3/4] Registering host module into VM & triggering host inspection..."
  vm <- createVM Nothing Nothing
  _ <- registerModuleFromImport vm hostMod

  -- 4. Trigger host function with active Wasm guest context
  putStrLn "[4/4] Invoking test_caller across boundary from Wasm guest..."
  fromGuest <- runWasmBytes vm callerGuestWasm "test_caller" [WasmI32 0]
  case fromGuest of
    Right [WasmI32 1] -> putStrLn "      test_caller -> inspect_caller returned success (VERIFIED)"
    other -> fail $ "Unexpected result from test_caller: " ++ show other

  rwOK <- readIORef readWriteRef
  csOK <- readIORef cStringRef
  csMaxOK <- readIORef cStringMaxRef
  fpOK <- readIORef framePtrsRef

  printf "      Memory read/write verified: %s\n" (show rwOK)
  printf "      C-String extraction verified: %s\n" (show csOK)
  printf "      Caller module/executor pointers non-null: %s\n" (show fpOK)

  unless (rwOK && csOK && csMaxOK && fpOK) $
    fail "Caller introspection checks did not all pass!"

  t1 <- getTime Monotonic
  let dur = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf ">>> Caller Introspection Suite completed in %.3f s\n\n" dur

  pure
    CallerMetrics
      { cmNullSafetyVerified = nullSafe
      , cmMemoryReadWriteOK = rwOK
      , cmCStringRoundTripOK = csOK
      , cmCStringMaxBoundedOK = csMaxOK
      , cmFramePointersVerified = fpOK
      , callermDurationSec = dur
      }
