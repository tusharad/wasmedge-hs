# Maintaining wasmedge-hs

This document explains how to keep `wasmedge-hs` in sync with upstream
WasmEdge releases and how to maintain long-term project health.

---

## Tracking Upstream WasmEdge Changes

### Workflow for each WasmEdge release

1. **Monitor the upstream release**

   Watch the [WasmEdge releases](https://github.com/WasmEdge/WasmEdge/releases)
   page. Subscribe to GitHub release notifications.

2. **Diff the public C header**

   The authoritative source of API changes is:
   ```
   include/api/wasmedge/wasmedge.h
   ```

   Run this to see what changed between two versions:
   ```bash
   git -C /path/to/WasmEdge diff 0.17.5..0.18.0 -- include/api/wasmedge/wasmedge.h
   ```

   Look for:
   - **New functions**: need new `foreign import` + shim
   - **Removed functions**: remove the FFI import; add a deprecation note
   - **Changed signatures**: update the shim and the FFI import
   - **New struct fields**: update `hsc2hs` `#size`/`#offset` macros
   - **New enum values**: update the Haskell enum and the `*ToC` conversion

3. **Check `wasmedge_deprecated.h`**

   WasmEdge marks deprecated functions in `include/api/wasmedge/wasmedge_deprecated.h`.
   Any function appearing there is on the removal track. Add a Haskell
   deprecation warning:
   ```haskell
   {-# DEPRECATED myFunction "WasmEdge deprecated this in 0.18; use newFunction instead" #-}
   ```

4. **Read the Changelog**

   `Changelog.md` in the WasmEdge repo describes breaking changes in plain
   English. Read the sections:
   - "Breaking changes"
   - "New features"
   - "Removed APIs"

5. **Update the ABI compatibility test**

   `test/Test/Unit/VersionSpec.hs` checks that the linked WasmEdge version
   matches the expected bounds. Update `shouldSatisfy (>= 18)` when
   targeting a new minor version.

6. **Update the `wasmedge-hs.cabal` version**

   The package version tracks WasmEdge: `MAJOR.MINOR.0.PATCH` where
   `MAJOR.MINOR` is the WasmEdge version. See [BACKWARDS_COMPAT.md](BACKWARDS_COMPAT.md).

---

## Adding a New WasmEdge Function

### Step 1: Add the C shim (if needed)

If the new function returns a struct by value, add:
1. A declaration in `cbits/wasmedge_hs_shims.h`
2. An implementation in `cbits/wasmedge_hs_shims.c`

If it returns `void` or a scalar (int, pointer), no shim is needed.

### Step 2: Add the Haskell FFI import

In the appropriate `WasmEdge.Internal.FFI.*` module:

```haskell
-- Returns struct by value → use shim
foreign import ccall unsafe "hs_WasmEdge_NewFunction"
  c_NewFunction :: Ptr CResult_ -> Ptr SomeTag -> IO ()

-- Returns void or scalar → import directly
foreign import ccall unsafe "WasmEdge_NewFunction"
  c_NewFunction :: Ptr SomeTag -> CString -> IO Word32
```

### Step 3: Add the public API wrapper

In the corresponding `WasmEdge.*` module, add a public function with:
- Idiomatic Haskell types
- `WasmResult` for fallible operations
- Haddock documentation
- A `bracket`-style variant if it creates a resource

### Step 4: Add a unit test

Even a minimal smoke test catches regressions.

---

## Versioning the Shims for ABI Breaks

If WasmEdge makes an ABI-breaking change (e.g., struct layout changes,
enum reordering), we need to support both old and new:

```c
// cbits/wasmedge_hs_shims.c
#include "wasmedge/wasmedge.h"

#if WASMEDGE_VERSION_MAJOR == 0 && WASMEDGE_VERSION_MINOR >= 18
// New 0.18 API
void hs_WasmEdge_NewThing(...) { ... }
#else
// Old 0.17 fallback
void hs_WasmEdge_NewThing(...) { ... }
#endif
```

On the Haskell side, use `cabal` flags:
```cabal
flag wasmedge-0-18
  description: Build against WasmEdge >= 0.18
  default: True
  manual: True
```

---

## CI Matrix

The CI runs on:
- GHC 9.6, 9.8, 9.10
- Linux x86_64, macOS arm64
- WasmEdge: current stable + previous stable

See `.github/workflows/ci.yml` for the full matrix.

To add a new GHC version to CI, add it to the `ghc-version` matrix in the
workflow file and to the `tested-with:` field in the cabal file.

---

## Updating Hackage

1. Bump the version in `wasmedge-hs.cabal`
2. Update `CHANGELOG.md`
3. Run `cabal check` — fix any warnings
4. Run `cabal sdist` to create the source distribution
5. Test the sdist: `cabal install --lib wasmedge-hs-X.Y.Z.tar.gz`
6. Upload to Hackage: `cabal upload dist-newstyle/sdist/*.tar.gz`

---

## Long-Term Health Checklist

- [ ] `cabal outdated` run quarterly; update bounds if tests pass
- [ ] WasmEdge releases subscribed on GitHub
- [ ] CI always green before merging PRs
- [ ] Breaking changes trigger a major/minor version bump per PVP
- [ ] `wasmedge_deprecated.h` checked each WasmEdge release
- [ ] `Changelog.md` updated for every release
