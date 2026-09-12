# Changelog for `wasmedge-hs`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the [Haskell Package Versioning Policy (PVP)](https://pvp.haskell.org/).

## [0.17.1.0] - 2026-09-13

### Added
- Released for WasmEdge 0.17.1 (stable release) with full upgrade path to 0.18.
- Added `WasmEdge.Caller` module providing safe host function access to guest memory (`getCallerMemory`, `readCallerMemory`, `writeCallerMemory`, `readCallerCString`).
- Added type-level host function registration via `ToHostFunc` typeclass, enabling direct registration of typed Haskell functions (e.g. `Int32 -> Int32 -> IO Int32`) without manual `WasmVal` unpacking.
- Added `builderAddHostFunc` in `WasmEdge.Module` for ergonomic host module construction.
- Added declarative `VMConfig` and `withVMConfig` in `WasmEdge.VM` inspired by Rust SDK's `VmBuilder`.
- Full Multi-version Stack build system support:
  - `stack.yaml`: Default LTS 22 (GHC 9.6.6)
  - `stack-lts-22.yaml`: Stackage LTS 22.44 (GHC 9.6.6)
  - `stack-lts-23.yaml`: Stackage LTS 23.18 (GHC 9.8.4)
  - `stack-lts-24.yaml`: Stackage LTS 24.33 (GHC 9.10.1)
  - `stack-nightly.yaml`: Stackage Nightly (GHC 9.12.x)
- License updated to MIT (Author: Tushar Adhatrao).
- Complete ground-up rewrite of Haskell bindings for WasmEdge 0.17.x / 0.18.x.
- Two-layer architecture:
  - `WasmEdge.Internal.FFI.*`: Raw C FFI bindings and shims.
  - Public safe modules: `WasmEdge`, `WasmEdge.VM`, `WasmEdge.Configure`, `WasmEdge.Types`, `WasmEdge.Value`, `WasmEdge.Module`, `WasmEdge.Function`, `WasmEdge.Table`, `WasmEdge.Memory`, `WasmEdge.Global`, `WasmEdge.Tag`, `WasmEdge.Plugin`, `WasmEdge.Async`, `WasmEdge.Compiler`, `WasmEdge.Statistics`, `WasmEdge.Store`, `WasmEdge.Executor`, `WasmEdge.Driver`, `WasmEdge.Log`, `WasmEdge.Error`.
- Strong phantom-typed ownership model (`OwnedCtx` vs `BorrowedCtx`) preventing double-free and use-after-free bugs.
- C shim layer (`cbits/wasmedge_hs_shims.c`) handling all struct-by-value C ABI conversions cleanly across ARM64 and x86_64.
- Bidirectional host function calling support (`createFunction`, `buildHostModule`, `builderAddFunction`) with automatic finalizer disarming upon ownership transfer.
- Ahead-Of-Time (AOT) compiler support via `compileFile` and `compileBytes`.
- Asynchronous WASM execution support via `asyncRunWasmFile`, `asyncRunWasmBytes`, `asyncExecute`.
- Plugin loading and discovery support via `loadDefaultPlugins`, `listPlugins`, `findPlugin`.
- Exception handling and tag instances support (`TagType`, `TagInstance`).
- Full test suite with 52 unit and property tests (HSpec + Hedgehog).
- Criterion microbenchmarks showing sub-microsecond pre-loaded execution.
- Comprehensive examples: `Hello`, `HostFunc`, `Plugin`, `AOTCompile`.
