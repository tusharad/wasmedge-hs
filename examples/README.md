# wasmedge-hs examples

Standalone Stack project containing example programs for the
[wasmedge-hs](https://github.com/tusharad/wasmedge-hs) Haskell bindings.

## Building

```bash
cd examples
stack build
```

## Examples

| Executable | Source | Description |
|---|---|---|
| `wasmedge-hs-example-hello` | `app/hello/Main.hs` | Run an inline `add(40, 2)` WASM module |
| `wasmedge-hs-example-hostfunc` | `app/hostfunc/Main.hs` | Register a Haskell host function and call it from WASM |
| `wasmedge-hs-example-aot` | `app/aot/Main.hs` | Compile WASM to a native shared library via AOT |
| `wasmedge-hs-example-plugin` | `app/plugin/Main.hs` | Discover and inspect WasmEdge plugins |

## Prerequisites

WasmEdge 0.17.x must be installed:

```bash
curl -sSf https://raw.githubusercontent.com/WasmEdge/WasmEdge/master/utils/install.sh | bash -s -- -v 0.17.1
```
