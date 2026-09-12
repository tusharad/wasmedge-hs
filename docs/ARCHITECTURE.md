# Architecture

## Overview

`wasmedge-hs` is a two-layer FFI package:

```
┌─────────────────────────────────────────────────┐
│  Public API layer  (WasmEdge.*)                 │
│  • Idiomatic Haskell types (WasmVal, Configure) │
│  • Bracket-style resource management            │
│  • WasmResult error monad                       │
├─────────────────────────────────────────────────┤
│  Internal layer  (WasmEdge.Internal.*)          │
│  • OwnedCtx / BorrowedCtx ownership model       │
│  • Storable instances for C struct layout        │
│  • Raw FFI imports (WasmEdge.Internal.FFI.*)    │
├─────────────────────────────────────────────────┤
│  C shim layer  (cbits/)                         │
│  • wasmedge_hs_shims.{h,c} — out-param wrappers │
│  • wasmedge_hs_int128.c — V128 helpers          │
│  Compiled directly by GHC                        │
├─────────────────────────────────────────────────┤
│  WasmEdge C API  (libwasmedge)                  │
└─────────────────────────────────────────────────┘
```

## Why Two Layers?

### Layer 1: Raw FFI (`WasmEdge.Internal.FFI.*`)

These modules contain only `foreign import` declarations with `Ptr` types.
They are intentionally thin — no business logic, no error handling.
This makes them easy to audit when the WasmEdge C API changes.

**Key rule**: Every function in `WasmEdge.Internal.FFI.*` must have a
1-to-1 correspondence with a C function signature in the shim header.

### Layer 2: Public API (`WasmEdge.*`)

These modules provide idiomatic Haskell APIs. They:
- Convert between Haskell types (Text, ByteString, WasmVal) and C types
- Manage resource lifetimes via `OwnedCtx` and `ForeignPtr`
- Convert `WasmEdge_Result` to `WasmEdgeError` exceptions
- Provide `bracket`-style resource management

## Ownership Model

All WasmEdge contexts fall into two categories:

### Owned contexts (`OwnedCtx tag`)
- Wrapped in `ForeignPtr` with a C delete function as finalizer
- Created by `WasmEdge_*Create` functions
- Example: `Configure`, `VM`, `Store`, `ModuleInstance` (when created from AST)

### Borrowed contexts (`BorrowedCtx tag`)
- Raw `Ptr tag` — no finalizer, no ownership
- Obtained via query functions (e.g., `VMGetStoreContext`, `CallingFrameGetModuleInstance`)
- **Lifetime is guaranteed by the parent context**
- The caller MUST NOT call `delete*` on a borrowed context

### 0.18 Finalized Module Instances

In WasmEdge 0.18+, `WasmEdge_ExecutorInstantiate` returns a
**finalized** module instance that is owned by the **Store**, not the caller.
We model this as:

```haskell
-- After instantiation, ModuleInstance is borrowed from the Store
instantiateModule :: Executor -> Store -> ASTModule -> IO BorrowedModuleInstance
```

The caller must not delete a finalized module instance. Deleting the Store
deletes all finalized modules within it.

## C Shim Layer

### Why shims?

GHC's FFI can only call C functions that:
1. Return void, or
2. Return a scalar type (int, pointer, double, etc.)

WasmEdge's C API returns many structs by value: `WasmEdge_String`,
`WasmEdge_Value`, `WasmEdge_Result`, `WasmEdge_ValType`.

GHC **cannot** marshal struct-by-value return values. Our shims convert
each such function into a void function with an extra `out*` parameter.

### Naming convention

```
WasmEdge_StringCreateByCString(...)  →  C function (struct by value)
hs_WasmEdge_StringCreateByCString(out, ...)  →  shim (out-param)
c_StringCreateByCString  →  Haskell FFI import of the shim
```

### No `c2hs`, no `inline-c`, no `cpphs`

All C interop goes through:
1. The shim `.c` file (compiled by GHC directly via `c-sources:`)
2. `foreign import ccall` declarations in `.hs` files
3. `hsc2hs` for struct layout constants (`#size`, `#offset`, `#alignment`)

This means the build has **zero external codegen dependencies**. Only
`hsc2hs` (bundled with GHC) is needed.

## Module Hierarchy

```
WasmEdge                          ← umbrella re-export
  Types                           ← Haskell types (WasmVal, ValType, ...)
  Error                           ← WasmEdgeError exception type
  Value                           ← WasmVal ↔ C encoding
  Log                             ← logging config
  Configure                       ← WasmEdge_ConfigureContext
  Statistics                      ← WasmEdge_StatisticsContext
  Store                           ← WasmEdge_StoreContext
  Executor                        ← WasmEdge_ExecutorContext
  Module                          ← WasmEdge_ModuleInstanceContext
  Function                        ← WasmEdge_FunctionInstanceContext
  Table                           ← WasmEdge_TableInstanceContext
  Memory                          ← WasmEdge_MemoryInstanceContext
  Global                          ← WasmEdge_GlobalInstanceContext
  Tag                             ← WasmEdge_TagInstanceContext (0.18+)
  VM                              ← WasmEdge_VMContext (high-level)
  Async                           ← WasmEdge_Async
  Compiler                        ← WasmEdge_CompilerContext
  Plugin                          ← WasmEdge_PluginContext

  Internal.Types                  ← phantom tags
  Internal.Ownership              ← OwnedCtx, BorrowedCtx
  Internal.Storable               ← Storable for C struct layout
  Internal.Utils                  ← Text/String helpers, checkResult
  Internal.FFI.Basic              ← version, log, string, bytes, result
  Internal.FFI.Value              ← ValType, Value gen/get
  Internal.FFI.Configure          ← configure + statistics
  Internal.FFI.AST                ← ASTModule
  Internal.FFI.Execution          ← loader, validator, executor, store, async
  Internal.FFI.Instance           ← all instance contexts
  Internal.FFI.VM                 ← VM
  Internal.FFI.Plugin             ← plugin
  Internal.FFI.Compiler           ← AOT compiler
  Internal.FFI.Experimental       ← experimental hooks
```

## Thread Safety

WasmEdge's "thread-safe" functions (those that can block, e.g., execution)
are imported with `safe` FFI. This allows the GHC RTS to run other Haskell
threads while the C function blocks.

"Unsafe" functions (those that return immediately, e.g., create/delete/query)
use `unsafe` FFI for performance.

**Rule**: Any FFI import that could block the OS thread uses `safe`.
Any FFI import that is guaranteed to return immediately uses `unsafe`.
