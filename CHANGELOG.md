# Changelog for `wasmedge-hs`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the [Haskell Package Versioning Policy (PVP)](https://pvp.haskell.org/).

## [0.18.0.0] - 2026-09-13

### Added
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
