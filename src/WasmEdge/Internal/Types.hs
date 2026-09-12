{-# LANGUAGE EmptyDataDecls #-}

{- |
Module      : WasmEdge.Internal.Types
Description : Phantom type tags and opaque context wrappers for WasmEdge C contexts
Copyright   : (c) wasmedge-hs contributors, 2026
License     : Apache-2.0
Stability   : internal

This module defines the phantom type tags used to distinguish different
WasmEdge context types at the Haskell type level, as well as the
'OwnedCtx' and 'BorrowedCtx' wrappers that encode ownership semantics.

__Do not import this module in user code.__ Use the public API modules instead.
-}
module WasmEdge.Internal.Types
  ( -- * Phantom context tags
    ConfigureTag
  , StatisticsTag
  , ASTModuleTag
  , FunctionTypeTag
  , TableTypeTag
  , MemoryTypeTag
  , TagTypeTag
  , GlobalTypeTag
  , ImportTypeTag
  , ExportTypeTag
  , CompilerTag
  , LoaderTag
  , ValidatorTag
  , ExecutorTag
  , StoreTag
  , ModuleInstanceTag
  , FunctionInstanceTag
  , TableInstanceTag
  , MemoryInstanceTag
  , TagInstanceTag
  , GlobalInstanceTag
  , CallingFrameTag
  , AsyncTag
  , VMTag
  , PluginTag

    -- * C struct phantom types
  , CWasmString
  , CWasmBytes
  , CWasmResult
  , CWasmValType
  , CWasmValue
  ) where

-- | Phantom tag for 'WasmEdge_ConfigureContext'
data ConfigureTag

-- | Phantom tag for 'WasmEdge_StatisticsContext'
data StatisticsTag

-- | Phantom tag for 'WasmEdge_ASTModuleContext'
data ASTModuleTag

-- | Phantom tag for 'WasmEdge_FunctionTypeContext'
data FunctionTypeTag

-- | Phantom tag for 'WasmEdge_TableTypeContext'
data TableTypeTag

-- | Phantom tag for 'WasmEdge_MemoryTypeContext'
data MemoryTypeTag

-- | Phantom tag for 'WasmEdge_TagTypeContext' (0.18+)
data TagTypeTag

-- | Phantom tag for 'WasmEdge_GlobalTypeContext'
data GlobalTypeTag

-- | Phantom tag for 'WasmEdge_ImportTypeContext'
data ImportTypeTag

-- | Phantom tag for 'WasmEdge_ExportTypeContext'
data ExportTypeTag

-- | Phantom tag for 'WasmEdge_CompilerContext'
data CompilerTag

-- | Phantom tag for 'WasmEdge_LoaderContext'
data LoaderTag

-- | Phantom tag for 'WasmEdge_ValidatorContext'
data ValidatorTag

-- | Phantom tag for 'WasmEdge_ExecutorContext'
data ExecutorTag

-- | Phantom tag for 'WasmEdge_StoreContext'
data StoreTag

-- | Phantom tag for 'WasmEdge_ModuleInstanceContext'
data ModuleInstanceTag

-- | Phantom tag for 'WasmEdge_FunctionInstanceContext'
data FunctionInstanceTag

-- | Phantom tag for 'WasmEdge_TableInstanceContext'
data TableInstanceTag

-- | Phantom tag for 'WasmEdge_MemoryInstanceContext'
data MemoryInstanceTag

-- | Phantom tag for 'WasmEdge_TagInstanceContext' (0.18+)
data TagInstanceTag

-- | Phantom tag for 'WasmEdge_GlobalInstanceContext'
data GlobalInstanceTag

-- | Phantom tag for 'WasmEdge_CallingFrameContext'
data CallingFrameTag

-- | Phantom tag for 'WasmEdge_Async'
data AsyncTag

-- | Phantom tag for 'WasmEdge_VMContext'
data VMTag

-- | Phantom tag for 'WasmEdge_PluginContext'
data PluginTag

-- | Phantom type for 'WasmEdge_String' C struct
data CWasmString

-- | Phantom type for 'WasmEdge_Bytes' C struct
data CWasmBytes

-- | Phantom type for 'WasmEdge_Result' C struct
data CWasmResult

-- | Phantom type for 'WasmEdge_ValType' C struct
data CWasmValType

-- | Phantom type for 'WasmEdge_Value' C struct
data CWasmValue
