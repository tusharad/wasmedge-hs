{-# LANGUAGE ForeignFunctionInterface #-}

{- |
Module      : WasmEdge.Internal.FFI.AST
Description : Raw FFI for WasmEdge AST module context
Copyright   : (c) wasmedge-hs contributors, 2026
License     : Apache-2.0
Stability   : internal
-}
module WasmEdge.Internal.FFI.AST
  ( c_ASTModuleDelete
  , c_ASTModuleListImportsLength
  , c_ASTModuleListImports
  , c_ASTModuleListExportsLength
  , c_ASTModuleListExports
  ) where

import Data.Word (Word32)
import Foreign.C
import Foreign.Ptr

import WasmEdge.Internal.Types

foreign import ccall unsafe "&WasmEdge_ASTModuleDelete"
  c_ASTModuleDelete :: FunPtr (Ptr ASTModuleTag -> IO ())

foreign import ccall unsafe "WasmEdge_ASTModuleListImportsLength"
  c_ASTModuleListImportsLength :: Ptr ASTModuleTag -> IO Word32

-- | List imports into a pre-allocated array of ImportTypeContext pointers.
foreign import ccall unsafe "WasmEdge_ASTModuleListImports"
  c_ASTModuleListImports ::
    Ptr ASTModuleTag ->
    Ptr (Ptr ImportTypeTag) ->
    Word32 ->
    IO Word32

foreign import ccall unsafe "WasmEdge_ASTModuleListExportsLength"
  c_ASTModuleListExportsLength :: Ptr ASTModuleTag -> IO Word32

-- | List exports into a pre-allocated array of ExportTypeContext pointers.
foreign import ccall unsafe "WasmEdge_ASTModuleListExports"
  c_ASTModuleListExports ::
    Ptr ASTModuleTag ->
    Ptr (Ptr ExportTypeTag) ->
    Word32 ->
    IO Word32
