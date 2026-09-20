{- |
Module      : WasmEdge.Types
Description : Core WebAssembly and WasmEdge types
Author      : Tushar Adhatrao <tusharadhatrao@gmail.com>
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : stable

Defines the Haskell representation of WebAssembly types used throughout
the binding: 'WasmVal', 'ValType', 'Mutability', 'ExternalType',
'Limit', and other shared data types.
-}
module WasmEdge.Types
  ( -- * WASM Values
    WasmVal (..)
  , FuncRef (..)
  , ExternRef (..)

    -- * Value types
  , ValType (..)

    -- * Limits
  , Limit (..)
  , unlimitedLimit

    -- * Mutability
  , Mutability (..)

    -- * External types (for import/export)
  , ExternalType (..)

    -- * Proposals
  , Proposal (..)

    -- * WASM standard
  , WasmStandard (..)

    -- * Host registrations
  , HostRegistration (..)

    -- * Run mode
  , RunMode (..)

    -- * Compiler settings
  , OptimizationLevel (..)
  , OutputFormat (..)
  ) where

import Control.DeepSeq (NFData)
import Data.Int (Int32, Int64)
import Data.WideWord.Int128 (Int128)
import Data.Word (Word32)
import Foreign.Ptr (Ptr)
import GHC.Generics (Generic)

-- ---------------------------------------------------------------------------
-- WasmVal
-- ---------------------------------------------------------------------------

{- | An opaque reference to a WasmEdge FunctionInstance.
Obtained via 'WasmEdge.Function.getFuncRef' or from a 'WasmVal'.
-}
newtype FuncRef = FuncRefPtr {funcRefPtr :: Ptr ()}
  deriving stock (Eq, Generic)
  deriving newtype (Show)
  deriving anyclass (NFData)

{- | An opaque reference to an external (host) object.
Created via 'WasmEdge.Function.mkExternRef'.
-}
newtype ExternRef = ExternRefPtr {externRefPtr :: Ptr ()}
  deriving stock (Eq, Generic)
  deriving newtype (Show)
  deriving anyclass (NFData)

{- | A WebAssembly value, covering all WASM numeric and reference types.

Use the constructor directly or via 'WasmEdge.Value.encode' and 'WasmEdge.Value.decode'.
-}
data WasmVal
  = -- | 32-bit integer (signed in Haskell, interchangeable with unsigned in WASM)
    WasmI32 !Int32
  | -- | 64-bit integer
    WasmI64 !Int64
  | -- | 32-bit IEEE 754 float
    WasmF32 !Float
  | -- | 64-bit IEEE 754 double
    WasmF64 !Double
  | -- | 128-bit SIMD vector (from @wide-word@)
    WasmV128 !Int128
  | -- | Function reference (nullable). 'Nothing' is a null funcref.
    WasmFuncRef !(Maybe FuncRef)
  | -- | External reference (nullable). 'Nothing' is a null externref.
    WasmExternRef !(Maybe ExternRef)
  deriving stock (Show, Eq, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- ValType
-- ---------------------------------------------------------------------------

{- | The type of a WebAssembly value. Used in function signatures and
global/table type descriptors.
-}
data ValType
  = -- | 32-bit integer
    I32
  | -- | 64-bit integer
    I64
  | -- | 32-bit float
    F32
  | -- | 64-bit float
    F64
  | -- | 128-bit SIMD vector
    V128
  | -- | Function reference
    FuncRef
  | -- | External reference
    ExternRef
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Limit
-- ---------------------------------------------------------------------------

-- | A WebAssembly limit (min, optional max) as used in table and memory types.
data Limit = Limit
  { limitMin :: !Word32
  , limitMax :: !(Maybe Word32)
  , limitShared :: !Bool
  -- ^ True for shared (threads proposal) memories
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (NFData)

-- | An unlimited limit (no max, not shared).
unlimitedLimit :: Word32 -> Limit
unlimitedLimit minVal = Limit minVal Nothing False

-- ---------------------------------------------------------------------------
-- Mutability
-- ---------------------------------------------------------------------------

-- | Global mutability.
data Mutability
  = -- | Immutable global
    Const
  | -- | Mutable global
    Var
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- ExternalType
-- ---------------------------------------------------------------------------

-- | The kind of entity imported or exported by a module.
data ExternalType
  = ExternalFunction
  | ExternalTable
  | ExternalMemory
  | ExternalGlobal
  | -- | 0.18+: exception tag (exception handling proposal)
    ExternalTag
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Proposal
-- ---------------------------------------------------------------------------

-- | WebAssembly proposals that can be enabled in 'WasmEdge.Configure.Configure'.
data Proposal
  = -- | 0: Import/export mutable globals
    ImportExportMutGlobals
  | -- | 1: Non-trap float-to-int conversions
    NonTrapFloatToIntConversions
  | -- | 2: Sign-extension operators
    SignExtensionOperators
  | -- | 3: Multiple return values
    MultiValue
  | -- | 4: Bulk memory operations
    BulkMemoryOperations
  | -- | 5: Reference types
    ReferenceTypes
  | -- | 6: SIMD (fixed-width)
    SIMD
  | -- | 7: Tail call optimization
    TailCall
  | -- | 8: Extended constant expressions
    ExtendedConst
  | -- | 9: Typed function references
    FunctionReferences
  | -- | 10: Garbage collection
    GC
  | -- | 11: Multiple memories
    MultiMemories
  | -- | 12: Relaxed SIMD
    RelaxedSIMD
  | -- | 13: Custom section annotations
    Annotations
  | -- | 14: Exception handling
    ExceptionHandling
  | -- | 15: 64-bit memory indices
    Memory64
  | -- | 16: Threads (shared memory + atomics)
    Threads
  | -- | 17: Component model
    ComponentModel
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- WasmStandard
-- ---------------------------------------------------------------------------

-- | A WASM standard preset that sets a group of proposals at once.
data WasmStandard
  = -- | WASM 1.0 (MVP)
    WASM1
  | -- | WASM 2.0
    WASM2
  | -- | WASM 3.0 (includes tail-call, extended-const, function refs, GC, EH, ...)
    WASM3
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- HostRegistration
-- ---------------------------------------------------------------------------

-- | Built-in host module registrations.
data HostRegistration
  = -- | Register the WASI module
    HostWASI
  | -- | @wasmedge_process@ was removed in WasmEdge 0.18. Use WASI instead.
    HostWasmEdgeProcess
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

{-# DEPRECATED HostWasmEdgeProcess "wasmedge_process was removed in WasmEdge 0.18. Use HostWASI instead." #-}

-- ---------------------------------------------------------------------------
-- RunMode (0.18+)
-- ---------------------------------------------------------------------------

-- | The execution mode for the WasmEdge runtime.
data RunMode
  = -- | Pure interpreter (always available)
    RunModeInterpreter
  | -- | AOT compiled (requires compiled binary)
    RunModeAOT
  | -- | Lazy JIT: compile on first function call (0.18+)
    RunModeLazyJIT
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- OptimizationLevel
-- ---------------------------------------------------------------------------

-- | AOT compiler optimization level.
data OptimizationLevel
  = -- | No optimization
    OptO0
  | -- | Basic optimization
    OptO1
  | -- | Default optimization
    OptO2
  | -- | Aggressive optimization
    OptO3
  | -- | Optimize for size
    OptOs
  | -- | Aggressive size optimization
    OptOz
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- OutputFormat
-- ---------------------------------------------------------------------------

-- | AOT compiler output format.
data OutputFormat
  = -- | Platform native shared library
    OutputNativeSharedLibrary
  | -- | Universal WASM (embeds native + bytecode)
    OutputWasmUniversal
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)
