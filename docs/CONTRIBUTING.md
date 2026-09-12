# Contributing to wasmedge-hs

## Getting Started

### Prerequisites

1. **GHC 9.6+** and **Stack 3.0+**:
   ```bash
   ghcup install stack
   ```

2. **WasmEdge 0.17.1**:
   On macOS (Homebrew):
   ```bash
   brew install wasmedge
   ```

   On Linux:
   ```bash
   curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install.sh | bash -s -- -v 0.17.1
   ```

### Building with Stack

```bash
cd wasmedge-hs
stack build
```

### Running tests

```bash
stack test
```

### Running benchmarks

```bash
stack bench
```

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
      Table.hs              Table instance
      Memory.hs             Memory instance
      Global.hs             Global instance
      Tag.hs                Tag instance (0.18+)
      VM.hs                 High-level VM
      Async.hs              Async execution results
      Compiler.hs           AOT compiler
      Plugin.hs             Plugin loading
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
    fixtures/               .wasm test fixtures
  bench/
    Main.hs                 Criterion benchmarks
  docs/
    ARCHITECTURE.md         Design decisions
    MAINTAINING.md          Upstream tracking workflow
    BACKWARDS_COMPAT.md     PVP + deprecation policy
    CONTRIBUTING.md         This file
  examples/                 Runnable example programs
```

---

## Coding Standards

### Public API modules

- Every exported function has a Haddock comment
- Resource-creating functions have a `with*` bracket variant
- Fallible functions return `IO (WasmResult a)` or throw `WasmEdgeError`
- No `unsafePerformIO` except in documented global singletons

### FFI modules (`WasmEdge.Internal.FFI.*`)

- Only `foreign import` declarations — no business logic
- `unsafe` for non-blocking functions, `safe` for blocking ones
- One comment per declaration explaining what it wraps
- Names mirror the C shim: `c_StringCreateByCString` wraps `hs_WasmEdge_StringCreateByCString`

### C shims

- Every shim function is a one-liner that does exactly one thing
- No C-side error handling (let WasmEdge report errors via `WasmEdge_Result`)
- `#include "wasmedge_hs_shims.h"` at the top of every `.c` file

### Ownership rules

- **Never** call a `delete` function on a borrowed pointer
- **Always** use `bracket` or `with*` for owned resources in user-facing code
- **Never** use `unsafeOwnedPtr` in public modules

---

## Running the ABI Compatibility Test

The test suite includes a version check that verifies the linked WasmEdge
version is within the expected bounds:

```bash
cabal test wasmedge-hs-test --test-option=--match="/Version/"
```

If this fails, you may have an incompatible WasmEdge installed.

---

## Submitting a Pull Request

1. Fork the repo and create a branch: `git checkout -b feature/my-feature`
2. Write tests for any new functionality
3. Ensure `cabal build` and `cabal test` pass
4. Run `cabal check` and fix any warnings
5. Update `CHANGELOG.md` under `Unreleased`
6. Submit the PR with a description of what changed and why
