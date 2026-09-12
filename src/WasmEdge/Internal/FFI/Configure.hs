-- |
-- Module      : WasmEdge.Internal.FFI.Configure
-- Description : Raw FFI for WasmEdge configure and statistics contexts
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : internal
{-# LANGUAGE ForeignFunctionInterface #-}
module WasmEdge.Internal.FFI.Configure
  ( -- * Configure context lifecycle
    c_ConfigureCreate
  , c_ConfigureDelete
    -- * Proposals
  , c_ConfigureAddProposal
  , c_ConfigureRemoveProposal
  , c_ConfigureHasProposal
  , c_ConfigureSetWASMStandard
    -- * Host registrations
  , c_ConfigureAddHostRegistration
  , c_ConfigureRemoveHostRegistration
  , c_ConfigureHasHostRegistration
    -- * Memory limits
  , c_ConfigureSetMaxMemoryPage
  , c_ConfigureGetMaxMemoryPage
    -- * Interpreter options
  , c_ConfigureSetForceInterpreter
  , c_ConfigureIsForceInterpreter
    -- * Run mode (0.18+)
  , c_ConfigureSetRunningMode
  , c_ConfigureGetRunningMode
    -- * Compiler options
  , c_ConfigureCompilerSetOptimizationLevel
  , c_ConfigureCompilerGetOptimizationLevel
  , c_ConfigureCompilerSetOutputFormat
  , c_ConfigureCompilerGetOutputFormat
  , c_ConfigureCompilerSetDumpIR
  , c_ConfigureCompilerIsDumpIR
  , c_ConfigureCompilerSetGenericBinary
  , c_ConfigureCompilerIsGenericBinary
  , c_ConfigureCompilerSetInterruptible
  , c_ConfigureCompilerIsInterruptible
    -- * Statistics options
  , c_ConfigureStatisticsSetInstructionCounting
  , c_ConfigureStatisticsIsInstructionCounting
  , c_ConfigureStatisticsSetCostMeasuring
  , c_ConfigureStatisticsIsCostMeasuring
  , c_ConfigureStatisticsSetTimeMeasuring
  , c_ConfigureStatisticsIsTimeMeasuring
    -- * Statistics context lifecycle
  , c_StatisticsCreate
  , c_StatisticsDelete
  , c_StatisticsGetInstrCount
  , c_StatisticsGetInstrPerSecond
  , c_StatisticsGetTotalCost
  , c_StatisticsSetCostTable
  , c_StatisticsSetCostLimit
  , c_StatisticsClear
  ) where

import Foreign.C
import Foreign.Ptr
import Data.Word (Word32, Word64)

import WasmEdge.Internal.Types

-- ---------------------------------------------------------------------------
-- Configure context
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "WasmEdge_ConfigureCreate"
  c_ConfigureCreate :: IO (Ptr ConfigureTag)

foreign import ccall unsafe "&WasmEdge_ConfigureDelete"
  c_ConfigureDelete :: FunPtr (Ptr ConfigureTag -> IO ())

-- Proposals — enum values mapped to Word32
foreign import ccall unsafe "WasmEdge_ConfigureAddProposal"
  c_ConfigureAddProposal :: Ptr ConfigureTag -> Word32 -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureRemoveProposal"
  c_ConfigureRemoveProposal :: Ptr ConfigureTag -> Word32 -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureHasProposal"
  c_ConfigureHasProposal :: Ptr ConfigureTag -> Word32 -> IO CBool

foreign import ccall unsafe "WasmEdge_ConfigureSetWASMStandard"
  c_ConfigureSetWASMStandard :: Ptr ConfigureTag -> Word32 -> IO ()

-- Host registrations
foreign import ccall unsafe "WasmEdge_ConfigureAddHostRegistration"
  c_ConfigureAddHostRegistration :: Ptr ConfigureTag -> Word32 -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureRemoveHostRegistration"
  c_ConfigureRemoveHostRegistration :: Ptr ConfigureTag -> Word32 -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureHasHostRegistration"
  c_ConfigureHasHostRegistration :: Ptr ConfigureTag -> Word32 -> IO CBool

-- Memory limits
foreign import ccall unsafe "WasmEdge_ConfigureSetMaxMemoryPage"
  c_ConfigureSetMaxMemoryPage :: Ptr ConfigureTag -> Word32 -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureGetMaxMemoryPage"
  c_ConfigureGetMaxMemoryPage :: Ptr ConfigureTag -> IO Word32

-- Interpreter options
foreign import ccall unsafe "WasmEdge_ConfigureSetForceInterpreter"
  c_ConfigureSetForceInterpreter :: Ptr ConfigureTag -> CBool -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureIsForceInterpreter"
  c_ConfigureIsForceInterpreter :: Ptr ConfigureTag -> IO CBool

-- Run mode (0.18+: Interpreter / AOT / LazyJIT)
foreign import ccall unsafe "WasmEdge_ConfigureSetRunningMode"
  c_ConfigureSetRunningMode :: Ptr ConfigureTag -> Word32 -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureGetRunningMode"
  c_ConfigureGetRunningMode :: Ptr ConfigureTag -> IO Word32

-- Compiler options
foreign import ccall unsafe "WasmEdge_ConfigureCompilerSetOptimizationLevel"
  c_ConfigureCompilerSetOptimizationLevel :: Ptr ConfigureTag -> Word32 -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureCompilerGetOptimizationLevel"
  c_ConfigureCompilerGetOptimizationLevel :: Ptr ConfigureTag -> IO Word32

foreign import ccall unsafe "WasmEdge_ConfigureCompilerSetOutputFormat"
  c_ConfigureCompilerSetOutputFormat :: Ptr ConfigureTag -> Word32 -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureCompilerGetOutputFormat"
  c_ConfigureCompilerGetOutputFormat :: Ptr ConfigureTag -> IO Word32

foreign import ccall unsafe "WasmEdge_ConfigureCompilerSetDumpIR"
  c_ConfigureCompilerSetDumpIR :: Ptr ConfigureTag -> CBool -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureCompilerIsDumpIR"
  c_ConfigureCompilerIsDumpIR :: Ptr ConfigureTag -> IO CBool

foreign import ccall unsafe "WasmEdge_ConfigureCompilerSetGenericBinary"
  c_ConfigureCompilerSetGenericBinary :: Ptr ConfigureTag -> CBool -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureCompilerIsGenericBinary"
  c_ConfigureCompilerIsGenericBinary :: Ptr ConfigureTag -> IO CBool

foreign import ccall unsafe "WasmEdge_ConfigureCompilerSetInterruptible"
  c_ConfigureCompilerSetInterruptible :: Ptr ConfigureTag -> CBool -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureCompilerIsInterruptible"
  c_ConfigureCompilerIsInterruptible :: Ptr ConfigureTag -> IO CBool

-- Statistics options
foreign import ccall unsafe "WasmEdge_ConfigureStatisticsSetInstructionCounting"
  c_ConfigureStatisticsSetInstructionCounting :: Ptr ConfigureTag -> CBool -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureStatisticsIsInstructionCounting"
  c_ConfigureStatisticsIsInstructionCounting :: Ptr ConfigureTag -> IO CBool

foreign import ccall unsafe "WasmEdge_ConfigureStatisticsSetCostMeasuring"
  c_ConfigureStatisticsSetCostMeasuring :: Ptr ConfigureTag -> CBool -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureStatisticsIsCostMeasuring"
  c_ConfigureStatisticsIsCostMeasuring :: Ptr ConfigureTag -> IO CBool

foreign import ccall unsafe "WasmEdge_ConfigureStatisticsSetTimeMeasuring"
  c_ConfigureStatisticsSetTimeMeasuring :: Ptr ConfigureTag -> CBool -> IO ()

foreign import ccall unsafe "WasmEdge_ConfigureStatisticsIsTimeMeasuring"
  c_ConfigureStatisticsIsTimeMeasuring :: Ptr ConfigureTag -> IO CBool

-- ---------------------------------------------------------------------------
-- Statistics context
-- ---------------------------------------------------------------------------

foreign import ccall unsafe "WasmEdge_StatisticsCreate"
  c_StatisticsCreate :: IO (Ptr StatisticsTag)

foreign import ccall unsafe "&WasmEdge_StatisticsDelete"
  c_StatisticsDelete :: FunPtr (Ptr StatisticsTag -> IO ())

foreign import ccall unsafe "WasmEdge_StatisticsGetInstrCount"
  c_StatisticsGetInstrCount :: Ptr StatisticsTag -> IO Word64

foreign import ccall unsafe "WasmEdge_StatisticsGetInstrPerSecond"
  c_StatisticsGetInstrPerSecond :: Ptr StatisticsTag -> IO CDouble

foreign import ccall unsafe "WasmEdge_StatisticsGetTotalCost"
  c_StatisticsGetTotalCost :: Ptr StatisticsTag -> IO Word64

foreign import ccall unsafe "WasmEdge_StatisticsSetCostTable"
  c_StatisticsSetCostTable :: Ptr StatisticsTag -> Ptr Word64 -> Word32 -> IO ()

foreign import ccall unsafe "WasmEdge_StatisticsSetCostLimit"
  c_StatisticsSetCostLimit :: Ptr StatisticsTag -> Word64 -> IO ()

foreign import ccall unsafe "WasmEdge_StatisticsClear"
  c_StatisticsClear :: Ptr StatisticsTag -> IO ()
