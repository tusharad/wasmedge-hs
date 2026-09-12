-- |
-- Module      : WasmEdge.Internal.FFI.Experimental
-- Description : Raw FFI for WasmEdge experimental hooks
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : internal
--
-- These are experimental features from @wasmedge_experimental.h@.
-- Use at your own risk; they may be removed in future WasmEdge versions.
{-# LANGUAGE ForeignFunctionInterface #-}
module WasmEdge.Internal.FFI.Experimental
  ( c_ExecutorRegisterPreHostFunction
  , c_ExecutorRegisterPostHostFunction
  , mkHookWrapper
  ) where

import Foreign.C
import Foreign.Ptr
import WasmEdge.Internal.Types

type RawHookT = Ptr () -> IO ()

foreign import ccall "wrapper"
  mkHookWrapper :: RawHookT -> IO (FunPtr RawHookT)

foreign import ccall safe "WasmEdge_ExecutorExperimentalRegisterPreHostFunction"
  c_ExecutorRegisterPreHostFunction
    :: Ptr ExecutorTag -> Ptr () -> FunPtr RawHookT -> IO ()

foreign import ccall safe "WasmEdge_ExecutorExperimentalRegisterPostHostFunction"
  c_ExecutorRegisterPostHostFunction
    :: Ptr ExecutorTag -> Ptr () -> FunPtr RawHookT -> IO ()
