-- |
-- Module      : WasmEdge.Compiler
-- Description : WasmEdge Ahead-Of-Time (AOT) compiler context
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : stable
--
-- The 'Compiler' context compiles WebAssembly bytecodes (.wasm) into
-- native shared objects (.so / .dylib) ahead-of-time for maximum execution speed.
module WasmEdge.Compiler
  ( -- * Compiler context
    Compiler
  , createCompiler
  , deleteCompiler
  , withCompiler

    -- * Compilation
  , compileFile
  , compileBytes

    -- * Internal / borrowed pointers
  , unsafeCompilerPtr
  , borrowCompiler
  ) where

import Control.Exception     (bracket, throwIO)
import Data.ByteString       (ByteString)
import Foreign.C.String      (withCString)
import Foreign.Ptr           (Ptr, FunPtr, nullPtr)

import WasmEdge.Error
import WasmEdge.Configure    (Configure, unsafeConfigurePtr)
import WasmEdge.Internal.Types     (CompilerTag)
import WasmEdge.Internal.Ownership (OwnedCtx, mkOwned, withOwned, finalizeOwned)
import WasmEdge.Internal.Storable  (allocaCResult)
import WasmEdge.Internal.Utils     (checkResult, withWasmBytes)
import WasmEdge.Internal.FFI.Compiler

-- ---------------------------------------------------------------------------
-- Compiler context
-- ---------------------------------------------------------------------------

-- | WasmEdge Ahead-Of-Time compiler context.
newtype Compiler = Compiler (OwnedCtx CompilerTag)

-- | Create an AOT 'Compiler' context with optional configuration settings.
createCompiler :: Maybe Configure -> IO Compiler
createCompiler mCfg = do
  cfgPtr <- maybe (pure nullPtr) unsafeConfigurePtr mCfg
  p <- c_CompilerCreate cfgPtr
  if p == nullPtr
    then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_CompilerCreate returned NULL"
    else Compiler <$> mkOwned (appFunPtr c_CompilerDelete) p

-- | Delete a 'Compiler'.
deleteCompiler :: Compiler -> IO ()
deleteCompiler (Compiler o) = finalizeOwned o

-- | Scoped 'Compiler'.
withCompiler :: Maybe Configure -> (Compiler -> IO a) -> IO a
withCompiler mCfg = bracket (createCompiler mCfg) deleteCompiler

-- ---------------------------------------------------------------------------
-- Compilation operations
-- ---------------------------------------------------------------------------

-- | Compile a WebAssembly file (.wasm) to a native shared library at the output path.
compileFile :: Compiler -> FilePath -> FilePath -> IO (WasmResult ())
compileFile (Compiler o) inPath outPath =
  withOwned o $ \p ->
  withCString inPath  $ \cIn ->
  withCString outPath $ \cOut ->
  allocaCResult $ \resPtr -> do
    c_CompilerCompile resPtr p cIn cOut
    checkResult resPtr

-- | Compile an in-memory WebAssembly binary to a native shared library at the output path.
compileBytes :: Compiler -> ByteString -> FilePath -> IO (WasmResult ())
compileBytes (Compiler o) bs outPath =
  withOwned o $ \p ->
  withWasmBytes bs $ \bytesPtr ->
  withCString outPath $ \cOut ->
  allocaCResult $ \resPtr -> do
    c_CompilerCompileFromBuffer resPtr p bytesPtr cOut
    checkResult resPtr

-- ---------------------------------------------------------------------------
-- Unsafe / internal pointer helpers
-- ---------------------------------------------------------------------------

-- | Extract the raw pointer of a 'Compiler'.
unsafeCompilerPtr :: Compiler -> IO (Ptr CompilerTag)
unsafeCompilerPtr (Compiler o) = withOwned o pure

-- | Create a borrowed 'Compiler' from a raw pointer (does not finalize).
borrowCompiler :: Ptr CompilerTag -> IO Compiler
borrowCompiler p = Compiler <$> mkOwned (\_ -> pure ()) p

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr fp p = mkDeleter fp p

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
