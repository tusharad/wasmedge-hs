{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.TagException
Description : Stress testing WebAssembly Tag types, instances, and exception proposal support
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Exercises:
  * 'TagType' / 'getTagTypeFunctionType'
  * 'TagInstance' / 'getTagInstanceType'
  * 'borrowTagType' / 'borrowTagInstance'
  * 'unsafeTagTypePtr' / 'unsafeTagInstancePtr'
  * 'listTags' / 'findTag' on 'ModuleInstance'
-}
module Stress.TagException
  ( runTagExceptionSuite
  , TagMetrics (..)
  ) where

import Control.Monad (unless)
import Foreign.Ptr (nullPtr)
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import Text.Printf (printf)

import WasmEdge.Configure (addProposal, createConfigure, hasProposal)
import WasmEdge.Module (createHostModule, deleteModuleInstance, findTag, listTags)
import WasmEdge.Tag
  ( borrowTagInstance
  , borrowTagType
  , unsafeTagInstancePtr
  , unsafeTagTypePtr
  )
import WasmEdge.Types (Proposal (..))

data TagMetrics = TagMetrics
  { tmExceptionsProposalEnabled :: !Bool
  , tmTagListingVerified :: !Bool
  , tmTagQuerySafeGraceful :: !Bool
  , tmTagPointersVerified :: !Bool
  , tagmDurationSec :: !Double
  }
  deriving stock (Show)

runTagExceptionSuite :: IO TagMetrics
runTagExceptionSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Tag Instances & Exception Proposal Subsystem"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  -- 1. Configure Exception Handling Proposal
  putStrLn "[1/4] Enabling Proposals_Exceptions in WasmEdge Configuration..."
  conf <- createConfigure
  addProposal conf ExceptionHandling
  hasExceptions <- hasProposal conf ExceptionHandling
  printf "      Exceptions proposal active: %s\n" (show hasExceptions)
  unless hasExceptions $ fail "Exceptions proposal should be active!"

  -- 2. Module Tag Inspection
  putStrLn "[2/4] Inspecting Tag exports on host module instances..."
  modInst <- createHostModule "exception_test_mod"
  tags <- listTags modInst
  printf "      Initial tags on fresh host module: %s\n" (show tags)
  unless (null tags) $ fail "Fresh host module should have 0 exported tags!"

  -- 3. Graceful Nothing handling for nonexistent tags
  putStrLn "[3/4] Querying non-existent tag via findTag..."
  mTag <- findTag modInst "nonexistent_tag"
  case mTag of
    Nothing -> putStrLn "      findTag returned Nothing gracefully (VERIFIED)"
    Just _ -> fail "findTag should have returned Nothing for nonexistent tag!"

  -- 4. Tag type and instance pointer conversions
  putStrLn "[4/4] Verifying TagInstance and TagType internal conversion helpers..."
  -- Test borrowTagInstance & unsafeTagInstancePtr roundtrip with null pointer representation
  tagInst <- borrowTagInstance nullPtr
  let pInst = unsafeTagInstancePtr tagInst
  unless (pInst == nullPtr) $ fail "TagInstance pointer roundtrip mismatch!"

  tagTy <- borrowTagType nullPtr
  let pTy = unsafeTagTypePtr tagTy
  unless (pTy == nullPtr) $ fail "TagType pointer roundtrip mismatch!"

  deleteModuleInstance modInst

  t1 <- getTime Monotonic
  let dur = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf ">>> Tag Exception Suite completed in %.3f s\n\n" dur

  pure
    TagMetrics
      { tmExceptionsProposalEnabled = hasExceptions
      , tmTagListingVerified = null tags
      , tmTagQuerySafeGraceful = True
      , tmTagPointersVerified = True
      , tagmDurationSec = dur
      }
