# Backwards Compatibility Policy

## Version Scheme

```
wasmedge-hs  X.Y.Z.W
             │ │ └─ Haskell-side patch (bug fixes, docs)
             │ └─── WasmEdge minor version
             └───── WasmEdge major version (0 for current WasmEdge 0.x series)
```

Examples:
- `0.18.0.0` — tracks WasmEdge 0.18, initial Haskell release
- `0.18.0.1` — bug fix in the Haskell bindings, same WasmEdge target
- `0.18.1.0` — new Haskell feature additions, same WasmEdge target
- `0.19.0.0` — tracks WasmEdge 0.19, may have breaking Haskell API changes

## PVP Compliance

We follow the [Haskell PVP](https://pvp.haskell.org/):

- **Patch releases** (`W`): bug fixes, documentation. No API changes.
- **Minor releases** (`Z`): new functions added to public API. Backwards compatible.
- **Major/minor-major releases** (`X.Y`): may contain breaking changes.
  Always corresponds to a WasmEdge major/minor version bump.

## What is a Breaking Change?

Any change that requires user code to be updated:

- Removing a function from a public module
- Changing a function's type signature
- Removing a constructor from a public type
- Changing the meaning of a function's result
- Removing a module from `exposed-modules`

## Deprecation Workflow

Before removing a function, deprecate it for at least **one minor release**:

```haskell
-- In the public module:
{-# DEPRECATED oldFunction "Use newFunction instead; will be removed in 0.20" #-}
oldFunction :: ...
oldFunction = newFunction
```

For functions deprecated by WasmEdge upstream, add:
```haskell
{-# DEPRECATED wasmedgeProcess "WasmEdge removed wasmedge_process in 0.18" #-}
```

## WasmEdge Version Compatibility

Each `wasmedge-hs` release targets a **single WasmEdge minor version**.
Multiple WasmEdge versions are not supported simultaneously in the same
`wasmedge-hs` version.

The ABI compatibility test in `Test.Unit.VersionSpec` will fail at
runtime if the linked WasmEdge library is out of the expected version range.

### The `WasmEdge.Deprecated` Module Strategy

When WasmEdge removes or renames a function between 0.17 and 0.18:

1. We create a `WasmEdge.Deprecated` module that re-exports the old names
   as deprecated wrappers:
   ```haskell
   -- WasmEdge.Deprecated
   {-# DEPRECATED runModule "Use WasmEdge.VM.runWasmFile instead" #-}
   runModule :: VM -> FilePath -> [WasmVal] -> IO (WasmResult [WasmVal])
   runModule = WasmEdge.VM.runWasmFile
   ```

2. The deprecated module is kept for one release cycle, then removed.

## Library Version Bounds

For downstream packages that depend on `wasmedge-hs`:

```cabal
build-depends: wasmedge-hs >= 0.18 && < 0.19
```

This correctly pins to the WasmEdge 0.18.x series.

If you want to support multiple WasmEdge series, use cabal flags:

```cabal
flag wasmedge-018
  description: Build against wasmedge-hs 0.18.x
  default: True

if flag(wasmedge-018)
  build-depends: wasmedge-hs >= 0.18 && < 0.19
else
  build-depends: wasmedge-hs >= 0.17 && < 0.18
```
