# Changelog for `wasmedge-hs`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the [Haskell Package Versioning Policy (PVP)](https://pvp.haskell.org/).

## [Unreleased]

_(nothing yet — open a PR against `develop`)_

---

## [0.18.1.0] - 2026-11-08

### Changed
- Target runtime upgraded to **WasmEdge 0.18.1**.
- Verified all 86 unit and property tests against WasmEdge 0.18.1 C headers and shared libraries.
- Updated `VersionSpec` suite to assert WasmEdge 0.18.1 ABI compatibility (`minor == 18`, `patch == 1`).
- Updated CI/CD matrix and deployment environments to install WasmEdge 0.18.1.
- Updated package metadata and Cabal source repository stanzas.

---

## [0.17.1.0] - 2026-11-07

**Initial public release.** Ground-up rewrite of Haskell bindings for WasmEdge 0.17.1.

### Added

- **WasmEdge.Caller** — Safe host function access to guest memory:
  `getCallerMemory`, `readCallerMemory`, `writeCallerMemory`, `readCallerCString`.
- **`ToHostFunc` typeclass** — Type-level host function registration.  
  Register typed Haskell functions (e.g. `Int32 -> Int32 -> IO Int32`) directly,
  without manual `WasmVal` unpacking.
- **`builderAddHostFunc`** in `WasmEdge.Module` for ergonomic host module construction.
- **Declarative `VMConfig` / `withVMConfig`** in `WasmEdge.VM` inspired by the Rust SDK's `VmBuilder`.
- **Multi-version Stack build matrix**:
  - `stack.yaml` / `stack-lts-22.yaml` — Stackage LTS 22.44 (GHC 9.6.6)
  - `stack-lts-23.yaml` — Stackage LTS 23.18 (GHC 9.8.4)
  - `stack-lts-24.yaml` — Stackage LTS 24.33 (GHC 9.10.1)
  - `stack-nightly.yaml` — Stackage Nightly (GHC 9.12.x)
- **Two-layer architecture**:
  - `WasmEdge.Internal.FFI.*` — Raw C FFI bindings and shims (no business logic).
  - Public safe modules: `WasmEdge`, `WasmEdge.VM`, `WasmEdge.Configure`,
    `WasmEdge.Types`, `WasmEdge.Value`, `WasmEdge.Module`, `WasmEdge.Function`,
    `WasmEdge.Table`, `WasmEdge.Memory`, `WasmEdge.Global`, `WasmEdge.Tag`,
    `WasmEdge.Plugin`, `WasmEdge.Async`, `WasmEdge.Compiler`,
    `WasmEdge.Statistics`, `WasmEdge.Store`, `WasmEdge.Executor`, `WasmEdge.Log`,
    `WasmEdge.Error`, `WasmEdge.Caller`, `WasmEdge.Bindgen`,
    `WasmEdge.Memory.Codec`, `WasmEdge.Memory.Alloc`.
- **Phantom-typed ownership model** (`OwnedCtx` vs `BorrowedCtx`) preventing
  double-free and use-after-free bugs via GHC finalizers.
- **C shim layer** (`cbits/wasmedge_hs_shims.c`) handling struct-by-value C ABI
  conversions cleanly across ARM64 (Apple Silicon) and x86_64 (Linux).
- **Bidirectional host function calling** (`createFunction`, `buildHostModule`,
  `builderAddFunction`) with automatic finalizer disarming on ownership transfer.
- **AOT compiler** support via `compileFile` and `compileBytes`
  (`WasmEdge.Compiler`).
- **Asynchronous WASM execution** via `asyncRunWasmFile`, `asyncRunWasmBytes`,
  `asyncExecute` (`WasmEdge.Async`).
- **Plugin system** — loading and discovery via `loadDefaultPlugins`,
  `listPlugins`, `findPlugin` (`WasmEdge.Plugin`).
- **Exception handling / Tag instances** (`TagType`, `TagInstance`) for
  WasmEdge 0.18+ exception proposals.
- **Full test suite** — 52 unit and property tests (HSpec + Hedgehog).
- **Criterion benchmarks** — sub-microsecond pre-loaded execution (~380 ns).
- **Comprehensive examples** — `Hello`, `HostFunc`, `Plugin`, `AOTCompile`,
  plus a full stress/API-suite with 20 scenario modules.
- **GitHub Actions CI** — format, HLint, multi-GHC build matrix, tests,
  examples build.
- **GitHub Actions Release pipeline** — Hackage upload (token-based), Haddock
  to GitHub Pages, GitHub Release creation.
- MIT License (Author: Tushar Adhatrao).

---

[Unreleased]: https://github.com/tusharad/wasmedge-hs/compare/v0.18.1.0...HEAD
[0.18.1.0]: https://github.com/tusharad/wasmedge-hs/compare/v0.17.1.0...v0.18.1.0
[0.17.1.0]: https://github.com/tusharad/wasmedge-hs/releases/tag/v0.17.1.0
