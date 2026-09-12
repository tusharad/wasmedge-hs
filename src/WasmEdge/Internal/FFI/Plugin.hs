{-# LANGUAGE ForeignFunctionInterface #-}

{- |
Module      : WasmEdge.Internal.FFI.Plugin
Description : Raw FFI for WasmEdge plugin context
Copyright   : (c) wasmedge-hs contributors, 2026
License     : Apache-2.0
Stability   : internal
-}
module WasmEdge.Internal.FFI.Plugin
  ( c_PluginLoadWithDefaultPaths
  , c_PluginLoadFromPath
  , c_PluginListPluginsLength
  , c_PluginListPlugins
  , c_PluginFind
  , c_PluginGetPluginName
  , c_PluginListModuleLength
  , c_PluginListModule
  , c_PluginCreateModule
  , c_PluginInitWASINN
  ) where

import Data.Word (Word32)
import Foreign.C
import Foreign.Ptr

import WasmEdge.Internal.Storable (CString_)
import WasmEdge.Internal.Types

foreign import ccall unsafe "WasmEdge_PluginLoadWithDefaultPaths"
  c_PluginLoadWithDefaultPaths :: IO ()

foreign import ccall unsafe "WasmEdge_PluginLoadFromPath"
  c_PluginLoadFromPath :: CString -> IO ()

foreign import ccall unsafe "WasmEdge_PluginListPluginsLength"
  c_PluginListPluginsLength :: IO Word32

foreign import ccall unsafe "WasmEdge_PluginListPlugins"
  c_PluginListPlugins :: Ptr CString_ -> Word32 -> IO Word32

foreign import ccall unsafe "hs_WasmEdge_PluginFind"
  c_PluginFind :: Ptr CString_ -> IO (Ptr PluginTag)

foreign import ccall unsafe "hs_WasmEdge_PluginGetPluginName"
  c_PluginGetPluginName :: Ptr CString_ -> Ptr PluginTag -> IO ()

foreign import ccall unsafe "WasmEdge_PluginListModuleLength"
  c_PluginListModuleLength :: Ptr PluginTag -> IO Word32

foreign import ccall unsafe "WasmEdge_PluginListModule"
  c_PluginListModule :: Ptr PluginTag -> Ptr CString_ -> Word32 -> IO Word32

foreign import ccall unsafe "hs_WasmEdge_PluginCreateModule"
  c_PluginCreateModule :: Ptr PluginTag -> Ptr CString_ -> IO (Ptr ModuleInstanceTag)

foreign import ccall unsafe "WasmEdge_PluginInitWASINN"
  c_PluginInitWASINN :: Ptr CString -> Word32 -> IO ()
