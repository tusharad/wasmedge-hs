{-# LANGUAGE ForeignFunctionInterface #-}

{- |
Module      : WasmEdge.Internal.FFI.Compiler
Description : Raw FFI for WasmEdge AOT compiler context
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : internal
-}
module WasmEdge.Internal.FFI.Compiler
  ( c_CompilerCreate
  , c_CompilerDelete
  , c_CompilerCompile
  , c_CompilerCompileFromBuffer
  ) where

import Foreign.C
import Foreign.Ptr
import WasmEdge.Internal.Storable (CBytes_, CResult_)
import WasmEdge.Internal.Types

foreign import ccall unsafe "WasmEdge_CompilerCreate"
  c_CompilerCreate :: Ptr ConfigureTag -> IO (Ptr CompilerTag)

foreign import ccall unsafe "&WasmEdge_CompilerDelete"
  c_CompilerDelete :: FunPtr (Ptr CompilerTag -> IO ())

foreign import ccall safe "hs_WasmEdge_CompilerCompile"
  c_CompilerCompile :: Ptr CResult_ -> Ptr CompilerTag -> CString -> CString -> IO ()

foreign import ccall safe "hs_WasmEdge_CompilerCompileFromBuffer"
  c_CompilerCompileFromBuffer ::
    Ptr CResult_ ->
    Ptr CompilerTag ->
    Ptr CBytes_ ->
    CString ->
    IO ()
