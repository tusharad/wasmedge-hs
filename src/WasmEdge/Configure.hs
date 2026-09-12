-- |
-- Module      : WasmEdge.Configure
-- Description : WasmEdge configuration context
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : stable
--
-- The 'Configure' context controls which WASM proposals are enabled,
-- how the compiler behaves, and which built-in host modules are registered.
--
-- Example:
--
-- @
-- import WasmEdge.Configure
-- import WasmEdge.Types
--
-- main :: IO ()
-- main = withConfigure $ \cfg -> do
--   addProposal cfg SIMD
--   addProposal cfg Threads
--   setMaxMemoryPage cfg 65536
--   setRunMode cfg RunModeAOT
--   -- pass cfg to VM or Executor...
-- @
module WasmEdge.Configure
  ( -- * Configure context
    Configure
  , createConfigure
  , deleteConfigure
  , withConfigure
    -- * Proposals
  , addProposal
  , removeProposal
  , hasProposal
  , setWasmStandard
    -- * Host registrations
  , addHostRegistration
  , removeHostRegistration
  , hasHostRegistration
    -- * Memory limits
  , setMaxMemoryPage
  , getMaxMemoryPage
    -- * Run mode (0.18+)
  , setRunMode
  , getRunMode
    -- * Interpreter options
  , setForceInterpreter
  , isForceInterpreter
    -- * Compiler options
  , CompilerOptions (..)
  , defaultCompilerOptions
  , setCompilerOptions
  , getCompilerOptions
    -- * Statistics options
  , StatisticsOptions (..)
  , defaultStatisticsOptions
  , setStatisticsOptions
  , getStatisticsOptions
    -- * Internal / borrowed pointers
  , unsafeConfigurePtr
  , borrowConfigure
  ) where

import Control.Exception   (bracket)
import Data.Word           (Word32)
import Foreign.C           (CBool (..))
import Foreign.Ptr

import WasmEdge.Types
import WasmEdge.Internal.Types     (ConfigureTag)
import WasmEdge.Internal.Ownership (OwnedCtx, mkOwned, withOwned, finalizeOwned)
import WasmEdge.Internal.FFI.Configure

-- ---------------------------------------------------------------------------
-- Configure newtype
-- ---------------------------------------------------------------------------

-- | Opaque WasmEdge configuration context.
-- Create with 'createConfigure' or use 'withConfigure' for scoped use.
newtype Configure = Configure (OwnedCtx ConfigureTag)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

-- | Create a new 'Configure' with default settings.
-- The caller is responsible for calling 'deleteConfigure' or using 'withConfigure'.
createConfigure :: IO Configure
createConfigure = do
  ptr <- c_ConfigureCreate
  Configure <$> mkOwned (\p -> c_ConfigureDelete `appFunPtr` p) ptr

-- | Explicitly delete a 'Configure' context.
-- After this call, the 'Configure' must not be used.
deleteConfigure :: Configure -> IO ()
deleteConfigure (Configure owned) = finalizeOwned owned

-- | Scoped 'Configure' context.
-- @withConfigure action@ creates a 'Configure', passes it to @action@,
-- and ensures it is deleted when @action@ completes (even on exception).
withConfigure :: (Configure -> IO a) -> IO a
withConfigure = bracket createConfigure deleteConfigure

-- ---------------------------------------------------------------------------
-- Proposals
-- ---------------------------------------------------------------------------

-- | Add a 'Proposal' to the configuration.
addProposal :: Configure -> Proposal -> IO ()
addProposal (Configure owned) p =
  withOwned owned $ \ptr -> c_ConfigureAddProposal ptr (proposalToC p)

-- | Remove a 'Proposal' from the configuration.
removeProposal :: Configure -> Proposal -> IO ()
removeProposal (Configure owned) p =
  withOwned owned $ \ptr -> c_ConfigureRemoveProposal ptr (proposalToC p)

-- | Check whether a 'Proposal' is currently enabled.
hasProposal :: Configure -> Proposal -> IO Bool
hasProposal (Configure owned) p =
  withOwned owned $ \ptr -> do
    CBool b <- c_ConfigureHasProposal ptr (proposalToC p)
    pure (b /= 0)

-- | Set all proposals to match a standard preset.
setWasmStandard :: Configure -> WasmStandard -> IO ()
setWasmStandard (Configure owned) std =
  withOwned owned $ \ptr -> c_ConfigureSetWASMStandard ptr (wasmStdToC std)

-- ---------------------------------------------------------------------------
-- Host registrations
-- ---------------------------------------------------------------------------

-- | Enable a built-in host module (e.g., WASI).
addHostRegistration :: Configure -> HostRegistration -> IO ()
addHostRegistration (Configure owned) hr =
  withOwned owned $ \ptr -> c_ConfigureAddHostRegistration ptr (hrToC hr)

-- | Disable a built-in host module.
removeHostRegistration :: Configure -> HostRegistration -> IO ()
removeHostRegistration (Configure owned) hr =
  withOwned owned $ \ptr -> c_ConfigureRemoveHostRegistration ptr (hrToC hr)

-- | Check whether a host module is registered.
hasHostRegistration :: Configure -> HostRegistration -> IO Bool
hasHostRegistration (Configure owned) hr =
  withOwned owned $ \ptr -> do
    CBool b <- c_ConfigureHasHostRegistration ptr (hrToC hr)
    pure (b /= 0)

-- ---------------------------------------------------------------------------
-- Memory limits
-- ---------------------------------------------------------------------------

-- | Set the maximum number of memory pages (default: 65536 = 4 GiB).
setMaxMemoryPage :: Configure -> Word32 -> IO ()
setMaxMemoryPage (Configure owned) n =
  withOwned owned $ \ptr -> c_ConfigureSetMaxMemoryPage ptr n

-- | Get the current maximum memory page count.
getMaxMemoryPage :: Configure -> IO Word32
getMaxMemoryPage (Configure owned) =
  withOwned owned c_ConfigureGetMaxMemoryPage

-- ---------------------------------------------------------------------------
-- Run mode (0.18+)
-- ---------------------------------------------------------------------------

-- | Set the execution run mode.
setRunMode :: Configure -> RunMode -> IO ()
setRunMode (Configure owned) mode =
  withOwned owned $ \ptr -> c_ConfigureSetRunningMode ptr (runModeToC mode)

-- | Get the current run mode.
getRunMode :: Configure -> IO RunMode
getRunMode (Configure owned) =
  withOwned owned $ \ptr -> do
    n <- c_ConfigureGetRunningMode ptr
    pure $ case n of
      0 -> RunModeInterpreter
      1 -> RunModeAOT
      2 -> RunModeLazyJIT
      _ -> RunModeInterpreter

-- ---------------------------------------------------------------------------
-- Force interpreter
-- ---------------------------------------------------------------------------

setForceInterpreter :: Configure -> Bool -> IO ()
setForceInterpreter (Configure owned) b =
  withOwned owned $ \ptr -> c_ConfigureSetForceInterpreter ptr (CBool (if b then 1 else 0))

isForceInterpreter :: Configure -> IO Bool
isForceInterpreter (Configure owned) =
  withOwned owned $ \ptr -> do
    CBool b <- c_ConfigureIsForceInterpreter ptr
    pure (b /= 0)

-- ---------------------------------------------------------------------------
-- Compiler options
-- ---------------------------------------------------------------------------

-- | AOT compiler options bundle.
data CompilerOptions = CompilerOptions
  { compOptLevel       :: !OptimizationLevel
  , compOutputFormat   :: !OutputFormat
  , compDumpIR         :: !Bool
  , compGenericBinary  :: !Bool
  , compInterruptible  :: !Bool
  }
  deriving stock (Show, Eq)

defaultCompilerOptions :: CompilerOptions
defaultCompilerOptions = CompilerOptions
  { compOptLevel       = OptO3
  , compOutputFormat   = OutputNativeSharedLibrary
  , compDumpIR         = False
  , compGenericBinary  = False
  , compInterruptible  = False
  }

setCompilerOptions :: Configure -> CompilerOptions -> IO ()
setCompilerOptions (Configure owned) opts =
  withOwned owned $ \ptr -> do
    c_ConfigureCompilerSetOptimizationLevel ptr (fromIntegral (fromEnum (compOptLevel opts)))
    c_ConfigureCompilerSetOutputFormat      ptr (fromIntegral (fromEnum (compOutputFormat opts)))
    c_ConfigureCompilerSetDumpIR            ptr (boolC (compDumpIR opts))
    c_ConfigureCompilerSetGenericBinary     ptr (boolC (compGenericBinary opts))
    c_ConfigureCompilerSetInterruptible     ptr (boolC (compInterruptible opts))

getCompilerOptions :: Configure -> IO CompilerOptions
getCompilerOptions (Configure owned) =
  withOwned owned $ \ptr -> do
    ol  <- c_ConfigureCompilerGetOptimizationLevel ptr
    fmt <- c_ConfigureCompilerGetOutputFormat      ptr
    di  <- c_ConfigureCompilerIsDumpIR             ptr
    gb  <- c_ConfigureCompilerIsGenericBinary      ptr
    ir  <- c_ConfigureCompilerIsInterruptible      ptr
    pure CompilerOptions
      { compOptLevel      = toEnum (fromIntegral ol)
      , compOutputFormat  = toEnum (fromIntegral fmt)
      , compDumpIR        = fromCBool di
      , compGenericBinary = fromCBool gb
      , compInterruptible = fromCBool ir
      }

-- ---------------------------------------------------------------------------
-- Statistics options
-- ---------------------------------------------------------------------------

data StatisticsOptions = StatisticsOptions
  { statInstructionCounting :: !Bool
  , statCostMeasuring       :: !Bool
  , statTimeMeasuring       :: !Bool
  }
  deriving stock (Show, Eq)

defaultStatisticsOptions :: StatisticsOptions
defaultStatisticsOptions = StatisticsOptions False False False

setStatisticsOptions :: Configure -> StatisticsOptions -> IO ()
setStatisticsOptions (Configure owned) opts =
  withOwned owned $ \ptr -> do
    c_ConfigureStatisticsSetInstructionCounting ptr (boolC (statInstructionCounting opts))
    c_ConfigureStatisticsSetCostMeasuring       ptr (boolC (statCostMeasuring opts))
    c_ConfigureStatisticsSetTimeMeasuring       ptr (boolC (statTimeMeasuring opts))

getStatisticsOptions :: Configure -> IO StatisticsOptions
getStatisticsOptions (Configure owned) =
  withOwned owned $ \ptr -> do
    ic <- c_ConfigureStatisticsIsInstructionCounting ptr
    cm <- c_ConfigureStatisticsIsCostMeasuring       ptr
    tm <- c_ConfigureStatisticsIsTimeMeasuring       ptr
    pure StatisticsOptions
      { statInstructionCounting = fromCBool ic
      , statCostMeasuring       = fromCBool cm
      , statTimeMeasuring       = fromCBool tm
      }

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- Enum conversions (kept internal)
proposalToC :: Proposal -> Word32
proposalToC = fromIntegral . fromEnum

wasmStdToC :: WasmStandard -> Word32
wasmStdToC = fromIntegral . fromEnum

hrToC :: HostRegistration -> Word32
hrToC = fromIntegral . fromEnum

runModeToC :: RunMode -> Word32
runModeToC = fromIntegral . fromEnum

boolC :: Bool -> CBool
boolC True  = CBool 1
boolC False = CBool 0

fromCBool :: CBool -> Bool
fromCBool (CBool 0) = False
fromCBool _         = True

-- | Extract the underlying pointer for passing to other contexts (unsafe).
unsafeConfigurePtr :: Configure -> IO (Ptr ConfigureTag)
unsafeConfigurePtr (Configure o) = withOwned o pure

-- | Create a borrowed 'Configure' context from an existing pointer.
borrowConfigure :: Ptr ConfigureTag -> IO Configure
borrowConfigure p = Configure <$> mkOwned (\_ -> pure ()) p

-- Helper to apply a FunPtr
appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr fp p = do
  let f = mkDeleter fp
  f p

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()

