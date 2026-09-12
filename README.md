# wasmedge-hs

Type-safe, idiomatic, high-performance Haskell FFI bindings for the [WasmEdge](https://wasmedge.org) WebAssembly runtime.

[![Build & Test](https://github.com/tusharad/wasmedge-hs/actions/workflows/ci.yml/badge.svg)](https://github.com/tusharad/wasmedge-hs/actions/workflows/ci.yml)
[![Hackage](https://img.shields.io/hackage/v/wasmedge-hs.svg)](https://hackage.haskell.org/package/wasmedge-hs)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Overview

`wasmedge-hs` provides a ground-up rework of the Haskell bindings for WasmEdge (supporting 0.17.x and 0.18.x). It is designed following modern Haskell FFI best practices:

- **Two-Layer Architecture**:
  - `WasmEdge.Internal.FFI.*`: Raw low-level C FFI with shim layer handling struct-by-value C ABI.
  - Safe, idiomatic Haskell interface with standard types (`Text`, `ByteString`, sum types).
- **Strong Phantom Ownership**:
  - `OwnedCtx tag` ensures resources are tracked and finalized via GC finalizers or explicit bracket calls.
  - Container-owned elements (such as `FunctionInstance` added to a `ModuleInstance`) are automatically disarmed to eliminate double-free bugs.
- **Full Feature Coverage**:
  - WebAssembly execution (one-shot and step-by-step pipeline)
  - Bidirectional host functions (calling Haskell functions from WASM)
  - Ahead-of-Time (AOT) compilation to native shared objects (`.so` / `.dylib`)
  - WASI support with arguments, environment variables, and preopened directories
  - Non-blocking asynchronous execution via `WasmEdge.Async`
  - Plug-in discovery and loading (e.g. `wasi_nn`, `wasi_logging`)
  - WasmEdge 0.18+ exception handling and Tag instances

---

## Installation & Prerequisites

Ensure that the WasmEdge C library is installed on your system:

### macOS (Homebrew)
```bash
brew install wasmedge
```

### Linux
```bash
curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install.sh | bash
```

### Building with Stack
```bash
# Default build (LTS 22 / GHC 9.6.6)
stack build
stack test

# Or choose a specific GHC / LTS version:
stack --stack-yaml stack-lts-22.yaml test  # GHC 9.6.6
stack --stack-yaml stack-lts-23.yaml test  # GHC 9.8.4
stack --stack-yaml stack-lts-24.yaml test  # GHC 9.10.1
stack --stack-yaml stack-nightly.yaml test # GHC 9.12.x
```

---

## Quick Start

### 1. Execute a WebAssembly Function

```haskell
{-# LANGUAGE OverloadedStrings #-}
import qualified Data.ByteString as BS
import WasmEdge.VM
import WasmEdge.Types

-- WASM bytecode defining: add(a, b) -> a + b
addWasm :: BS.ByteString
addWasm = ...

main :: IO ()
main = do
  withVM Nothing Nothing $ \vm -> do
    res <- runWasmBytes vm addWasm "add" [WasmI32 40, WasmI32 2]
    case res of
      Right [WasmI32 ans] -> putStrLn $ "Result: " ++ show ans -- 42
      Left err            -> putStrLn $ "Error: " ++ show err
```

### 2. Export Haskell Functions to WebAssembly

```haskell
{-# LANGUAGE OverloadedStrings #-}
import WasmEdge.VM
import WasmEdge.Types
import WasmEdge.Function
import WasmEdge.Module

haskellAddOne :: CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal])
haskellAddOne _ [WasmI32 n] = pure $ Right [WasmI32 (n + 1)]
haskellAddOne _ args        = pure $ Right args

main :: IO ()
main = do
  withFunctionType [I32] [I32] $ \fnType ->
    withFunction fnType haskellAddOne $ \hostFn -> do
      hostMod <- buildHostModule "host_module" $ \b ->
        builderAddFunction b "add_one" hostFn

      withVM Nothing Nothing $ \vm -> do
        Right () <- registerModuleFromImport vm hostMod
        res <- runWasmBytes vm guestWasm "call_host" [WasmI32 99]
        print res -- Right [WasmI32 100]

-- Or write typed Haskell functions directly without manual WasmVal pattern matching:
hostMod2 <- buildHostModule "host_module" $ \b -> do
  builderAddHostFunc b "add" $ \(x :: Int32) (y :: Int32) -> pure (x + y) :: IO Int32
  builderAddHostFunc b "print_guest" $ \frame (ptr :: Word32) (len :: Word32) -> do
    mBytes <- readCallerMemory frame 0 ptr len
    maybe (pure ()) print mBytes
```

### 3. Ahead-Of-Time (AOT) Compilation

```haskell
import WasmEdge.Compiler
import WasmEdge.Configure
import WasmEdge.Types (OptimizationLevel (..))

compileToNative :: IO ()
compileToNative = do
  withConfigure $ \cfg -> do
    setCompilerOptions cfg (defaultCompilerOptions { compOptLevel = OptO3 })
    withCompiler (Just cfg) $ \compiler -> do
      res <- compileFile compiler "input.wasm" "output.so"
      case res of
        Right () -> putStrLn "Compiled successfully to output.so"
        Left err -> putStrLn $ "Compilation failed: " ++ show err
```

---

## Examples

Run any of the included examples using `cabal run`:

- `cabal run wasmedge-hs-example-hello`: Minimal WASM execution
- `cabal run wasmedge-hs-example-hostfunc`: Calling Haskell callbacks from WebAssembly
- `cabal run wasmedge-hs-example-plugin`: Dynamic plugin discovery and module introspection
- `cabal run wasmedge-hs-example-aot`: AOT compilation of bytecode to optimized native code

---

## Benchmarks

Microbenchmarks are implemented using Criterion (`cabal run wasmedge-hs-bench --enable-benchmarks`):

| Benchmark Scenario | Mean Latency |
| :--- | :--- |
| Pre-loaded Function Execution | **~380 ns** |
| One-shot WASM Execution (`runWasmBytes`) | **~26 μs** |
| Step-by-step Pipeline (`load/validate/instantiate/exec`) | **~26 μs** |
| VM Lifecycle (`createVM`/`deleteVM`) | **~23 μs** |

---

## Documentation

- [Architecture Design](docs/ARCHITECTURE.md)
- [Backwards Compatibility Guidelines](docs/BACKWARDS_COMPAT.md)
- [Maintenance & Upgrades](docs/MAINTAINING.md)
- [Contributing Guide](docs/CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

---

## License

MIT License. Copyright (c) 2026 Tushar Adhatrao. See [LICENSE](LICENSE) for details.
