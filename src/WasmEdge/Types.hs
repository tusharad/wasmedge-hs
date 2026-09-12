-- |
-- Module      : WasmEdge.Types
-- Description : Core WASM value types and related enumerations
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : stable
--
-- Defines the Haskell representation of WebAssembly types used throughout
-- the binding: 'WasmVal', 'ValType', 'Mutability', 'ExternalType',
-- 'Limit', and other shared data types.
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

import Data.Int    (Int32, Int64)
import Data.Word   (Word32, Word64)
import Data.WideWord.Int128 (Int128)
import Foreign.Ptr (Ptr)
import GHC.Generics (Generic)
import Control.DeepSeq (NFData)

-- ---------------------------------------------------------------------------
-- WasmVal
-- ---------------------------------------------------------------------------

-- | An opaque reference to a WasmEdge FunctionInstance.
-- Obtained via 'WasmEdge.Function.getFuncRef' or from a 'WasmVal'.
newtype FuncRef = FuncRefPtr { funcRefPtr :: Ptr () }
  deriving stock (Eq, Generic)
  deriving newtype (Show)
  deriving anyclass (NFData)

-- | An opaque reference to an external (host) object.
-- Created via 'WasmEdge.Function.mkExternRef'.
newtype ExternRef = ExternRefPtr { externRefPtr :: Ptr () }
  deriving stock (Eq, Generic)
  deriving newtype (Show)
  deriving anyclass (NFData)

-- | A WebAssembly value, covering all WASM numeric and reference types.
--
-- Use the constructor directly or via 'WasmEdge.Value.encode' and 'WasmEdge.Value.decode'.
data WasmVal
  = WasmI32   !Int32
    -- ^ 32-bit integer (signed in Haskell, interchangeable with unsigned in WASM)
  | WasmI64   !Int64
    -- ^ 64-bit integer
  | WasmF32   !Float
    -- ^ 32-bit IEEE 754 float
  | WasmF64   !Double
    -- ^ 64-bit IEEE 754 double
  | WasmV128  !Int128
    -- ^ 128-bit SIMD vector (from @wide-word@)
  | WasmFuncRef   !(Maybe FuncRef)
    -- ^ Function reference (nullable). 'Nothing' is a null funcref.
  | WasmExternRef !(Maybe ExternRef)
    -- ^ External reference (nullable). 'Nothing' is a null externref.
  deriving stock (Show, Eq, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- ValType
-- ---------------------------------------------------------------------------

-- | The type of a WebAssembly value. Used in function signatures and
-- global/table type descriptors.
data ValType
  = I32        -- ^ 32-bit integer
  | I64        -- ^ 64-bit integer
  | F32        -- ^ 32-bit float
  | F64        -- ^ 64-bit float
  | V128       -- ^ 128-bit SIMD vector
  | FuncRef    -- ^ Function reference
  | ExternRef  -- ^ External reference
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Limit
-- ---------------------------------------------------------------------------

-- | A WebAssembly limit (min, optional max) as used in table and memory types.
data Limit = Limit
  { limitMin    :: !Word32
  , limitMax    :: !(Maybe Word32)
  , limitShared :: !Bool   -- ^ True for shared (threads proposal) memories
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
  = Const  -- ^ Immutable global
  | Var    -- ^ Mutable global
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
  | ExternalTag   -- ^ 0.18+: exception tag (exception handling proposal)
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Proposal
-- ---------------------------------------------------------------------------

-- | WebAssembly proposals that can be enabled in 'WasmEdge.Configure.Configure'.
data Proposal
  = ImportExportMutGlobals       -- ^ 0: Import/export mutable globals
  | NonTrapFloatToIntConversions -- ^ 1: Non-trap float-to-int conversions
  | SignExtensionOperators       -- ^ 2: Sign-extension operators
  | MultiValue                   -- ^ 3: Multiple return values
  | BulkMemoryOperations         -- ^ 4: Bulk memory operations
  | ReferenceTypes               -- ^ 5: Reference types
  | SIMD                         -- ^ 6: SIMD (fixed-width)
  | TailCall                     -- ^ 7: Tail call optimization
  | ExtendedConst                -- ^ 8: Extended constant expressions
  | FunctionReferences           -- ^ 9: Typed function references
  | GC                           -- ^ 10: Garbage collection
  | MultiMemories                -- ^ 11: Multiple memories
  | RelaxedSIMD                  -- ^ 12: Relaxed SIMD
  | Annotations                  -- ^ 13: Custom section annotations
  | ExceptionHandling            -- ^ 14: Exception handling
  | Memory64                     -- ^ 15: 64-bit memory indices
  | Threads                      -- ^ 16: Threads (shared memory + atomics)
  | ComponentModel               -- ^ 17: Component model
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- | The integer value sent to the C API for each proposal.
proposalToC :: Proposal -> Word32
proposalToC = fromIntegral . fromEnum

-- ---------------------------------------------------------------------------
-- WasmStandard
-- ---------------------------------------------------------------------------

-- | A WASM standard preset that sets a group of proposals at once.
data WasmStandard
  = WASM1   -- ^ WASM 1.0 (MVP)
  | WASM2   -- ^ WASM 2.0
  | WASM3   -- ^ WASM 3.0 (includes tail-call, extended-const, function refs, GC, EH, ...)
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

wasmStandardToC :: WasmStandard -> Word32
wasmStandardToC = \case
  WASM1 -> 0
  WASM2 -> 1
  WASM3 -> 2

-- ---------------------------------------------------------------------------
-- HostRegistration
-- ---------------------------------------------------------------------------

-- | Built-in host module registrations.
data HostRegistration
  = HostWASI              -- ^ Register the WASI module
  | HostWasmEdgeProcess   -- ^ Register wasmedge_process (deprecated 0.18)
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

hostRegistrationToC :: HostRegistration -> Word32
hostRegistrationToC = \case
  HostWASI            -> 0
  HostWasmEdgeProcess -> 1

-- ---------------------------------------------------------------------------
-- RunMode (0.18+)
-- ---------------------------------------------------------------------------

-- | The execution mode for the WasmEdge runtime.
data RunMode
  = RunModeInterpreter  -- ^ Pure interpreter (always available)
  | RunModeAOT          -- ^ AOT compiled (requires compiled binary)
  | RunModeLazyJIT      -- ^ Lazy JIT: compile on first function call (0.18+)
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

runModeToC :: RunMode -> Word32
runModeToC = \case
  RunModeInterpreter -> 0
  RunModeAOT         -> 1
  RunModeLazyJIT     -> 2

-- ---------------------------------------------------------------------------
-- OptimizationLevel
-- ---------------------------------------------------------------------------

-- | AOT compiler optimization level.
data OptimizationLevel
  = OptO0  -- ^ No optimization
  | OptO1  -- ^ Basic optimization
  | OptO2  -- ^ Default optimization
  | OptO3  -- ^ Aggressive optimization
  | OptOs  -- ^ Optimize for size
  | OptOz  -- ^ Aggressive size optimization
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- OutputFormat
-- ---------------------------------------------------------------------------

-- | AOT compiler output format.
data OutputFormat
  = OutputNativeSharedLibrary  -- ^ Platform native shared library
  | OutputWasmUniversal        -- ^ Universal WASM (embeds native + bytecode)
  deriving stock (Show, Eq, Ord, Bounded, Enum, Generic)
  deriving anyclass (NFData)
