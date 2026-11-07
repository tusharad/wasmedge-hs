# Contributing to wasmedge-hs

Thank you for your interest in contributing! This guide explains how to get
set up, our coding standards, and the process for submitting pull requests.

---

## Getting Started

### Prerequisites

1. **GHC 9.6+** and either **Stack 3.0+** or **Cabal 3.10+**:
   ```bash
   ghcup install ghc 9.10.1
   ghcup install cabal 3.12.1.0
   # or for Stack:
   ghcup install stack
   ```

2. **WasmEdge 0.18.1**:

   On macOS (Homebrew):
   ```bash
   brew install wasmedge
   ```

   On Linux:
   ```bash
   curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install.sh \
     | sudo bash -s -- -v 0.18.1 -p /usr/local
   sudo ldconfig
   ```

---

### Building with Cabal

```bash
cd wasmedge-hs
cabal update
cabal build
cabal test
cabal check           # must pass before any release
cabal haddock         # build local docs
```

### Building with Stack

```bash
cd wasmedge-hs
stack build
stack test

# Multi-GHC builds:
stack --stack-yaml stack-lts-22.yaml build  # GHC 9.6.6
stack --stack-yaml stack-lts-23.yaml build  # GHC 9.8.4
stack --stack-yaml stack-lts-24.yaml build  # GHC 9.10.1
stack --stack-yaml stack-nightly.yaml build # GHC 9.12.x
```

### Running benchmarks

```bash
cabal run wasmedge-hs-bench --enable-benchmarks
# or:
stack bench
```

---

## Branching Strategy

We use a simplified Git-flow:

| Branch | Purpose |
|:---|:---|
| `main` | Stable. Only release commits land here. Protected branch. |
| `develop` | Integration branch. All feature PRs target `develop`. |
| `feat/<name>` | New feature — branch from and PR into `develop`. |
| `fix/<name>` | Bug fix — branch from and PR into `develop`. |
| `chore/<name>` | CI, docs, infrastructure — branch from and PR into `develop`. |

**Release flow:**
1. All work merges into `develop` via PR review.
2. When ready to release: open a PR `develop → main`.
3. Merge `develop → main`.
4. Create and push an annotated tag: `git tag -a v0.17.1.0 -m "Release 0.17.1.0" && git push origin v0.17.1.0`.
5. The `release.yml` workflow fires automatically, runs tests, publishes to Hackage, and deploys Haddock to GitHub Pages.

---

## Project Layout

```
wasmedge-hs/
  cbits/                    C shim layer (compiled by GHC)
    wasmedge_hs_shims.h     Out-param wrapper declarations
    wasmedge_hs_shims.c     Implementations
    wasmedge_hs_int128.c    V128 / uint128_t helpers
  include/
    wasmedge_hs.h           Umbrella include for hsc2hs
  src/
    WasmEdge.hs             Top-level re-exports
    WasmEdge/
      Types.hs              Core WASM types
      Error.hs              WasmEdgeError exception
      Value.hs              WasmVal encoding/decoding
      Log.hs                Logging configuration
      Configure.hs          Configure context
      Statistics.hs         Statistics context
      Store.hs              Store context
      Executor.hs           Executor context
      Module.hs             Module instance
      Function.hs           Function instance + host functions
      Function/
        Memory.hs           Lifted host functions with memory access
      Caller.hs             Caller frame and memory access
      Table.hs              Table instance
      Memory.hs             Memory instance
      Memory/
        Codec.hs            WasmMemory / WasmJSON codecs
        Alloc.hs            Linear memory allocation helpers
      Global.hs             Global instance
      Tag.hs                Tag instance (WasmEdge 0.18+)
      VM.hs                 High-level VM
      Async.hs              Async execution results
      Compiler.hs           AOT compiler
      Plugin.hs             Plugin loading
      Bindgen.hs            High-level guest calling helpers
      Internal/
        Types.hs            Phantom type tags
        Ownership.hs        OwnedCtx / BorrowedCtx
        Storable.hs         C struct layout helpers
        Utils.hs            Text/String/Result utilities
        FFI/
          Basic.hs          version, log, string, bytes, result
          Value.hs          ValType + Value gen/get
          Configure.hs      configure + statistics
          AST.hs            ASTModule
          Execution.hs      loader, validator, executor, store, async
          Instance.hs       all instance contexts
          VM.hs             VM
          Plugin.hs         plugin
          Compiler.hs       AOT compiler
          Experimental.hs   experimental hooks
  test/
    Main.hs                 Test entry point
    Test/Unit/              HSpec unit tests
    Test/Property/          Hedgehog property tests
    data/                   .wasm test fixtures
  bench/
    Main.hs                 Criterion benchmarks
  examples/                 Runnable example programs
  docs/
    ARCHITECTURE.md         Design decisions
    MAINTAINING.md          Upstream tracking workflow
    BACKWARDS_COMPAT.md     PVP + deprecation policy
    CONTRIBUTING.md         This file
  .github/
    workflows/
      ci.yml                Build / test CI (runs on every push + PR)
      release.yml           Hackage publish + GitHub Pages (runs on tag)
```

---

## Coding Standards

### Public API modules

- Every exported function **must** have a Haddock comment (`-- |`).
- Resource-creating functions must have a `with*` bracket variant.
- Fallible functions return `IO (WasmResult a)` or throw `WasmEdgeError`.
- No `unsafePerformIO` except in documented global singletons.
- Export lists must be **explicit** — no wildcard `(..)` exports on public modules.

### FFI modules (`WasmEdge.Internal.FFI.*`)

- Only `foreign import` declarations — no business logic.
- Use `unsafe` for non-blocking functions, `safe` for blocking ones.
- One comment per declaration explaining what C function it wraps.
- Names mirror the C shim: `c_StringCreateByCString` wraps
  `hs_WasmEdge_StringCreateByCString`.

### C shims (`cbits/`)

- Every shim function is a one-liner that does exactly one thing.
- No C-side error handling — let WasmEdge report errors via `WasmEdge_Result`.
- `#include "wasmedge_hs_shims.h"` at the top of every `.c` file.

### Ownership rules

- **Never** call a `delete` function on a borrowed pointer.
- **Always** use `bracket` or `with*` for owned resources in user-facing code.
- **Never** use `unsafeOwnedPtr` in public modules.

### Code style

- Formatting: **fourmolu** (config in `fourmolu.yaml` / defaults).
- Linting: **HLint** with config in `.hlint.yaml`.
- Run before committing:
  ```bash
  fourmolu -i src/ test/ examples/
  hlint src/ test/ examples/
  ```

---

## Running the ABI Compatibility Test

The test suite includes a version check that verifies the linked WasmEdge
version matches the expected bounds:

```bash
# Cabal:
cabal test wasmedge-hs-test --test-option=--match="/Version/"
# Stack:
stack test --test-arguments="--match=/Version/"
```

If this fails, you may have an incompatible WasmEdge version installed.

---

## Submitting a Pull Request

1. Fork the repo and create a feature branch from `develop`:
   ```bash
   git checkout develop
   git pull
   git checkout -b feat/my-feature
   ```
2. Write tests for any new functionality.
3. Ensure all checks pass:
   ```bash
   fourmolu -m check src/ test/
   hlint src/ test/
   cabal build && cabal test
   cabal check
   ```
4. Update `CHANGELOG.md` under `[Unreleased]`.
5. Submit the PR **targeting `develop`** with a clear description of what
   changed and why.

---

## Release Process (Maintainer Only)

See [docs/MAINTAINING.md](MAINTAINING.md) for the full release workflow.

Quick summary:
```bash
# 1. Merge develop → main via PR
# 2. On main:
git tag -a v0.17.1.0 -m "Release wasmedge-hs 0.17.1.0"
git push origin v0.17.1.0
# 3. The release.yml workflow automatically:
#    - Runs format/lint/test
#    - cabal sdist + haddock
#    - Uploads to Hackage
#    - Creates GitHub Release
#    - Deploys Haddock to GitHub Pages
```
