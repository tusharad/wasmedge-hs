-- |
-- Module      : WasmEdge
-- Description : Re-exports for convenient import of the WasmEdge Haskell bindings
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : stable
--
-- Import this module for access to the most commonly used functions:
--
-- @
-- import WasmEdge
--
-- main :: IO ()
-- main = withVM Nothing Nothing $ \vm ->
--   runWasmFile vm "hello.wasm" "main" [] >>= print
-- @
--
-- For specialized features, import the dedicated modules:
--
-- * "WasmEdge.Configure" — WASM proposals, compiler settings, run mode
-- * "WasmEdge.VM"        — High-level VM API
-- * "WasmEdge.Module"    — Host module building
-- * "WasmEdge.Function"  — Host function creation
-- * "WasmEdge.Memory"    — Memory instance access
-- * "WasmEdge.Plugin"    — Plugin loading
-- * "WasmEdge.Async"     — Async execution
-- * "WasmEdge.Log"       — Logging configuration
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
    -- * Version
  , version
  , versionMajor
  , versionMinor
  , versionPatch
    -- * VM (re-exported from "WasmEdge.VM")
  , VM
  , withVM
  , runWasmFile
  , runWasmBytes
  , loadWasmFile
  , loadWasmBytes
  , validate
  , instantiate
  , execute
  ) where

import Data.Text        (Text)
import Foreign.C        (peekCString)
import Data.Word        (Word32)

import WasmEdge.Types
import WasmEdge.Error
import WasmEdge.VM     (VM, withVM, runWasmFile, runWasmBytes,
                         loadWasmFile, loadWasmBytes, validate, instantiate, execute)
import WasmEdge.Internal.FFI.Basic

-- ---------------------------------------------------------------------------
-- Version
-- ---------------------------------------------------------------------------

-- | The version string of the linked WasmEdge library (e.g., @\"0.18.0\"@).
version :: IO Text
version = do
  cs <- c_VersionGet
  str <- peekCString cs
  pure (fromString str)
  where
    fromString = Data.Text.pack
    Data.Text.pack = id  -- placeholder, use real Data.Text

-- | Major version number.
versionMajor :: IO Word32
versionMajor = c_VersionGetMajor

-- | Minor version number.
versionMinor :: IO Word32
versionMinor = c_VersionGetMinor

-- | Patch version number.
versionPatch :: IO Word32
versionPatch = c_VersionGetPatch
