{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ExplicitNamespaces #-}

{- |
Module      : Lib
Description : Top-level export of all stress suites and testbed utilities
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental
-}
module Stress.Lib
  ( -- * Stress Suites (1 - 10)
    module Stress.BigMemory
  , module Stress.ConcurrentPool
  , module Stress.AsyncTimeout
  , module Stress.HostPipeline
  , module Stress.ChaosFault
  , module Stress.AOTWorkflow
  , module Stress.StatisticsCost
  , module Stress.LeakCheck
  , module Stress.ComplexData

    -- * New API Coverage & Cross-Language Suites (11 - 19)
  , module Stress.PluginWorkflow
  , module Stress.TableIndirect
  , module Stress.GlobalState
  , module Stress.TagException
  , module Stress.LowLevelPipeline
  , module Stress.StoreReflection
  , module Stress.WASILifecycle
  , module Stress.CallerIntrospection
  , module Stress.LoggingDiagnostic

    -- * Bytecode Fixtures
  , module Stress.WasmBytecode
  ) where

import Stress.AOTWorkflow
import Stress.AsyncTimeout
import Stress.BigMemory
import Stress.CallerIntrospection
import Stress.ChaosFault
import Stress.ComplexData
import Stress.ConcurrentPool
import Stress.GlobalState
import Stress.HostPipeline
import Stress.LeakCheck
import Stress.LoggingDiagnostic
import Stress.LowLevelPipeline
import Stress.PluginWorkflow
import Stress.StatisticsCost
import Stress.StoreReflection
import Stress.TableIndirect
import Stress.TagException
import Stress.WASILifecycle
import Stress.WasmBytecode
