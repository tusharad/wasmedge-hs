{- |
Module      : WasmEdge
Description : Re-exports for convenient import of the WasmEdge Haskell bindings
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : stable

Import this module for access to the most commonly used functions:

@
import WasmEdge

main :: IO ()
main = withVM Nothing Nothing $ \vm ->
  runWasmFile vm "hello.wasm" "main" [] >>= print
@

For specialized features, import the dedicated modules:

* "WasmEdge.Configure" — WASM proposals, compiler settings, run mode
* "WasmEdge.VM"        — High-level VM API
* "WasmEdge.Module"    — Host module building
* "WasmEdge.Function"  — Host function creation and 'ToHostFunc'
* "WasmEdge.Caller"    — Caller frame and memory access
* "WasmEdge.Memory"    — Memory instance access
* "WasmEdge.Plugin"    — Plugin loading
* "WasmEdge.Async"     — Async execution
* "WasmEdge.Log"       — Logging configuration
-}
module WasmEdge
  ( -- * Core types (re-exported from "WasmEdge.Types")
    WasmVal (..)
  , ValType (..)
  , Mutability (..)
  , Limit (..)
  , Proposal (..)
  , RunMode (..)

    -- * Error types (re-exported from "WasmEdge.Error")
  , WasmEdgeError (..)
  , WasmResult
  , ErrCategory (..)
  , formatError

    -- * Version
  , version
  , versionMajor
  , versionMinor
  , versionPatch

    -- * VM (re-exported from "WasmEdge.VM")
  , VM
  , withVM
  , VMConfig (..)
  , defaultVMConfig
  , withVMConfig
  , runWasmFile
  , runWasmBytes
  , loadWasmFile
  , loadWasmBytes
  , validate
  , instantiate
  , execute

    -- * Host Functions (re-exported from "WasmEdge.Function")
  , ToHostFunc (..)
  , WasmValType (..)
  , WasmReturn (..)
  , createHostFunction
  , withHostFunction
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32)
import Foreign.C (peekCString)

import WasmEdge.Error
import WasmEdge.Function
  ( ToHostFunc (..)
  , WasmReturn (..)
  , WasmValType (..)
  , createHostFunction
  , withHostFunction
  )
import WasmEdge.Internal.FFI.Basic
import WasmEdge.Types
import WasmEdge.VM
  ( VM
  , VMConfig (..)
  , defaultVMConfig
  , execute
  , instantiate
  , loadWasmBytes
  , loadWasmFile
  , runWasmBytes
  , runWasmFile
  , validate
  , withVM
  , withVMConfig
  )

-- ---------------------------------------------------------------------------
-- Version
-- ---------------------------------------------------------------------------

-- | The version string of the linked WasmEdge library (e.g., @\"0.18.0\"@).
version :: IO Text
version = do
  cs <- c_VersionGet
  str <- peekCString cs
  pure (T.pack str)

-- | Major version number.
versionMajor :: IO Word32
versionMajor = c_VersionGetMajor

-- | Minor version number.
versionMinor :: IO Word32
versionMinor = c_VersionGetMinor

-- | Patch version number.
versionPatch :: IO Word32
versionPatch = c_VersionGetPatch
