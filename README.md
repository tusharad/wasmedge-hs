# wasmedge-hs

Type-safe, idiomatic, high-performance Haskell FFI bindings for the [WasmEdge](https://wasmedge.org) WebAssembly runtime.

[![Build & Test](https://github.com/tusharad/wasmedge-hs/actions/workflows/ci.yml/badge.svg)](https://github.com/tusharad/wasmedge-hs/actions/workflows/ci.yml)
[![Release](https://github.com/tusharad/wasmedge-hs/actions/workflows/release.yml/badge.svg)](https://github.com/tusharad/wasmedge-hs/actions/workflows/release.yml)
[![Hackage](https://img.shields.io/hackage/v/wasmedge-hs.svg)](https://hackage.haskell.org/package/wasmedge-hs)
[![Hackage Deps](https://img.shields.io/hackage-deps/v/wasmedge-hs.svg)](https://hackage.haskell.org/package/wasmedge-hs)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Haddock](https://img.shields.io/badge/docs-Haddock-blue.svg)](https://tusharad.github.io/wasmedge-hs/)

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

### 1. Install the WasmEdge C runtime

**macOS (Homebrew)**
```bash
brew install wasmedge
```

**Linux**
```bash
curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install.sh \
  | sudo bash -s -- -v 0.18.1 -p /usr/local
```

### 2. Add `wasmedge-hs` to your project

**Cabal** (`cabal.project` / `.cabal`):
```cabal
-- your-package.cabal
build-depends: wasmedge-hs >= 0.18.1 && < 0.19
```

```bash
cabal build
cabal test
```

**Stack** (`stack.yaml`):
```yaml
extra-deps:
  - wasmedge-hs-0.18.1.0
```

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

-- Minimal WebAssembly module implementing: add(a: i32, b: i32) -> i32
addWasm :: BS.ByteString
addWasm = BS.pack
  [ 0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00  -- magic + version
  , 0x01, 0x07, 0x01, 0x60, 0x02, 0x7F, 0x7F, 0x01, 0x7F  -- type: (i32, i32) -> i32
  , 0x03, 0x02, 0x01, 0x00                              -- function section
  , 0x07, 0x07, 0x01, 0x03, 0x61, 0x64, 0x64, 0x00, 0x00  -- export "add"
  , 0x0A, 0x09, 0x01, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x6A, 0x0B  -- body
  ]

main :: IO ()
main = do
  result <- withVM Nothing Nothing $ \vm ->
    runWasmBytes vm addWasm "add" [WasmI32 40, WasmI32 2]
  case result of
    Right [WasmI32 ans] -> putStrLn $ "Result: 40 + 2 = " ++ show ans -- 42
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
```

For typed host functions (no manual `WasmVal` unpacking), use `builderAddHostFunc`:

```haskell
buildHostModule "host_module" $ \b -> do
  builderAddHostFunc b "add" $ \(x :: Int32) (y :: Int32) -> pure (x + y) :: IO Int32
```

See `cabal run wasmedge-hs-example-hostfunc` for the complete, runnable example.


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

Run any of the included examples:

```bash
# Cabal
cabal run wasmedge-hs-example-hello
cabal run wasmedge-hs-example-hostfunc
cabal run wasmedge-hs-example-plugin
cabal run wasmedge-hs-example-aot

# Stack
stack run wasmedge-hs-example-hello
```

- **`hello`** — Minimal WASM execution (add two i32 values)
- **`hostfunc`** — Calling Haskell callbacks from WebAssembly
- **`plugin`** — Dynamic plugin discovery and module introspection
- **`aot`** — AOT compilation of bytecode to optimized native code

---

## Benchmarks

Microbenchmarks with Criterion:

```bash
cabal run wasmedge-hs-bench --enable-benchmarks
```

| Benchmark Scenario | Mean Latency |
| :--- | :--- |
| Pre-loaded Function Execution | **~380 ns** |
| One-shot WASM Execution (`runWasmBytes`) | **~26 μs** |
| Step-by-step Pipeline (`load/validate/instantiate/exec`) | **~26 μs** |
| VM Lifecycle (`createVM`/`deleteVM`) | **~23 μs** |

---

## Supported GHC Versions

| GHC | Stackage LTS | Status |
| :--- | :--- | :--- |
| 9.6.6 | LTS 22 | ✅ Tested |
| 9.8.4 | LTS 23 | ✅ Tested |
| 9.10.1 | LTS 24 | ✅ Tested |
| 9.12.x | Nightly | 🧪 Experimental |

---

## Documentation

- [Haddock API Docs](https://tusharad.github.io/wasmedge-hs/) (GitHub Pages)
- [Hackage Package Page](https://hackage.haskell.org/package/wasmedge-hs)
- [Architecture Design](docs/ARCHITECTURE.md)
- [Backwards Compatibility Guidelines](docs/BACKWARDS_COMPAT.md)
- [Maintenance & Upgrades](docs/MAINTAINING.md)
- [Contributing Guide](docs/CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

---

## Branching Strategy

| Branch | Purpose |
| :--- | :--- |
| `main` | Stable, release-tagged. Only release commits land here. |
| `develop` | Integration branch. All PRs target `develop` first. |
| `feat/*` | Feature branches — merge into `develop` via PR. |
| `fix/*` | Bug-fix branches — merge into `develop` via PR. |
| `chore/*` | Infrastructure, docs, CI changes. |

Releases are created by merging `develop → main`, then pushing an annotated tag `v<version>`.

---

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full guide.
Quick start:

```bash
git clone https://github.com/tusharad/wasmedge-hs
cd wasmedge-hs
brew install wasmedge        # macOS
stack build
stack test
```

---

## License

MIT License. Copyright (c) 2026 Tushar Adhatrao. See [LICENSE](LICENSE) for details.
