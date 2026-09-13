{- |
Module      : WasmBytecode
Description : Pre-compiled binary WebAssembly modules for stress testing and verification
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

This module provides standard, validated WASM binaries encoded as 'ByteString's.
These bytecodes are used across all stress suites to test:
  1. Recursive compute-heavy workloads ('fibWasm')
  2. Multi-megabyte dynamic memory allocation and linear memory access ('memoryOpsWasm')
  3. Host-to-guest and guest-to-host FFI pipelines ('hostImportWasm')
  4. Intentional traps, division by zero, memory violations, and infinite loops ('chaosWasm')
-}
module Stress.WasmBytecode
  ( -- * Pure Compute
    fibWasm
  , addWasm

    -- * Linear Memory Operations
  , memoryOpsWasm

    -- * Host Function Imports
  , hostImportWasm

    -- * Chaos and Fault Injection
  , chaosWasm
  , corruptedMagicWasm
  , corruptedSectionWasm

    -- * Caller Introspection Guest
  , callerGuestWasm
  ) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS

-- | Standard WASM header: magic "\0asm" and version 1.
wasmHeader :: [Integer]
wasmHeader = [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]

{- | Minimal addition module:

@
(module
  (func (export "add") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.add))
@
-}
addWasm :: ByteString
addWasm =
  BS.pack $
    map fromIntegral $
      wasmHeader
        ++ [ -- Type section: (i32, i32) -> i32
             0x01
           , 0x07
           , 0x01
           , 0x60
           , 0x02
           , 0x7F
           , 0x7F
           , 0x01
           , 0x7F
           , -- Function section: func 0 has type 0
             0x03
           , 0x02
           , 0x01
           , 0x00
           , -- Export section: "add" -> func 0
             0x07
           , 0x07
           , 0x01
           , 0x03
           , 0x61
           , 0x64
           , 0x64
           , 0x00
           , 0x00
           , -- Code section
             0x0A
           , 0x09
           , 0x01
           , 0x07
           , 0x00
           , 0x20
           , 0x00
           , 0x20
           , 0x01
           , 0x6A
           , 0x0B
           ]

{- | Recursive Fibonacci module:

@
(module
  (func $fib (export "fib") (param i32) (result i32)
    local.get 0
    i32.const 1
    i32.le_s
    if (result i32)
      local.get 0
    else
      local.get 0
      i32.const 1
      i32.sub
      call 0
      local.get 0
      i32.const 2
      i32.sub
      call 0
      i32.add
    end))
@
-}
fibWasm :: ByteString
fibWasm =
  BS.pack $
    map fromIntegral $
      wasmHeader
        ++ [ -- Type section: 1 type: (i32) -> i32
             0x01
           , 0x06
           , 0x01
           , 0x60
           , 0x01
           , 0x7F
           , 0x01
           , 0x7F
           , -- Function section: func 0 uses type 0
             0x03
           , 0x02
           , 0x01
           , 0x00
           , -- Export section: "fib" -> func 0
             0x07
           , 0x07
           , 0x01
           , 0x03
           , 0x66
           , 0x69
           , 0x62
           , 0x00
           , 0x00
           , -- Code section:
             -- func body length: 28 bytes (0x1C)
             -- total code section length: 1 count + 1 size + 28 bytes = 30 bytes (0x1E)
             0x0A
           , 0x1E
           , 0x01
           , 0x1C
           , 0x00
           , 0x20
           , 0x00 -- local.get 0
           , 0x41
           , 0x01 -- i32.const 1
           , 0x4C -- i32.le_s
           , 0x04
           , 0x7F -- if (result i32)
           , 0x20
           , 0x00 --   local.get 0
           , 0x05 -- else
           , 0x20
           , 0x00 --   local.get 0
           , 0x41
           , 0x01 --   i32.const 1
           , 0x6B --   i32.sub
           , 0x10
           , 0x00 --   call 0
           , 0x20
           , 0x00 --   local.get 0
           , 0x41
           , 0x02 --   i32.const 2
           , 0x6B --   i32.sub
           , 0x10
           , 0x00 --   call 0
           , 0x6A --   i32.add
           , 0x0B -- end (if)
           , 0x0B -- end (func)
           ]

-- | Linear Memory Operations module:
memoryOpsWasm :: ByteString
memoryOpsWasm =
  BS.pack $
    map fromIntegral $
      wasmHeader
        ++ [ -- Type section: 4 function types (size 22 = 0x16)
             0x01
           , 0x16
           , 0x04
           , -- Type 0: (i32, i32) -> () [write_u32]
             0x60
           , 0x02
           , 0x7F
           , 0x7F
           , 0x00
           , -- Type 1: (i32) -> i32 [read_u32, grow_memory]
             0x60
           , 0x01
           , 0x7F
           , 0x01
           , 0x7F
           , -- Type 2: () -> i32 [memory_size]
             0x60
           , 0x00
           , 0x01
           , 0x7F
           , -- Type 3: (i32, i32, i32) -> i32 [fill_pattern]
             0x60
           , 0x03
           , 0x7F
           , 0x7F
           , 0x7F
           , 0x01
           , 0x7F
           , -- Function section: 5 functions (size 6 = 0x06)
             0x03
           , 0x06
           , 0x05
           , 0x00
           , 0x01
           , 0x01
           , 0x02
           , 0x03
           , -- Memory section: 1 memory, min=1, max=1024 (size 5 = 0x05)
             0x05
           , 0x05
           , 0x01
           , 0x01
           , 0x01
           , 0x80
           , 0x08
           , -- Export section: 6 exports (size 76 = 0x4C)
             0x07
           , 0x4C
           , 0x06
           , -- "memory" -> memory 0
             0x06
           , 0x6D
           , 0x65
           , 0x6D
           , 0x6F
           , 0x72
           , 0x79
           , 0x02
           , 0x00
           , -- "write_u32" -> func 0
             0x09
           , 0x77
           , 0x72
           , 0x69
           , 0x74
           , 0x65
           , 0x5F
           , 0x75
           , 0x33
           , 0x32
           , 0x00
           , 0x00
           , -- "read_u32" -> func 1
             0x08
           , 0x72
           , 0x65
           , 0x61
           , 0x64
           , 0x5F
           , 0x75
           , 0x33
           , 0x32
           , 0x00
           , 0x01
           , -- "grow_memory" -> func 2
             0x0B
           , 0x67
           , 0x72
           , 0x6F
           , 0x77
           , 0x5F
           , 0x6D
           , 0x65
           , 0x6D
           , 0x6F
           , 0x72
           , 0x79
           , 0x00
           , 0x02
           , -- "memory_size" -> func 3
             0x0B
           , 0x6D
           , 0x65
           , 0x6D
           , 0x6F
           , 0x72
           , 0x79
           , 0x5F
           , 0x73
           , 0x69
           , 0x7A
           , 0x65
           , 0x00
           , 0x03
           , -- "fill_pattern" -> func 4
             0x0C
           , 0x66
           , 0x69
           , 0x6C
           , 0x6C
           , 0x5F
           , 0x70
           , 0x61
           , 0x74
           , 0x74
           , 0x65
           , 0x72
           , 0x6E
           , 0x00
           , 0x04
           , -- Code section: 5 functions (size 75 = 0x4B)
             0x0A
           , 0x4B
           , 0x05
           , -- Func 0 (write_u32): size 9
             0x09
           , 0x00
           , 0x20
           , 0x00
           , 0x20
           , 0x01
           , 0x36
           , 0x02
           , 0x00
           , 0x0B
           , -- Func 1 (read_u32): size 7
             0x07
           , 0x00
           , 0x20
           , 0x00
           , 0x28
           , 0x02
           , 0x00
           , 0x0B
           , -- Func 2 (grow_memory): size 6
             0x06
           , 0x00
           , 0x20
           , 0x00
           , 0x40
           , 0x00
           , 0x0B
           , -- Func 3 (memory_size): size 4
             0x04
           , 0x00
           , 0x3F
           , 0x00
           , 0x0B
           , -- Func 4 (fill_pattern): size 43 (0x2B)
             0x2B
           , 0x01
           , 0x02
           , 0x7F -- 2 local i32s: $i (local 3), $sum (local 4)
           , 0x03
           , 0x40 -- loop
           , 0x20
           , 0x03 --   local.get $i (3)
           , 0x20
           , 0x01 --   local.get $len (1)
           , 0x49 --   i32.lt_u
           , 0x04
           , 0x40 --   if
           , 0x20
           , 0x00 --     local.get $off (0)
           , 0x20
           , 0x03 --     local.get $i (3)
           , 0x6A --     i32.add
           , 0x20
           , 0x02 --     local.get $val (2)
           , 0x3A
           , 0x00
           , 0x00 --     i32.store8 align=0 offset=0
           , 0x20
           , 0x04 --     local.get $sum (4)
           , 0x20
           , 0x02 --     local.get $val (2)
           , 0x6A --     i32.add
           , 0x21
           , 0x04 --     local.set $sum (4)
           , 0x20
           , 0x03 --     local.get $i (3)
           , 0x41
           , 0x01 --     i32.const 1
           , 0x6A --     i32.add
           , 0x21
           , 0x03 --     local.set $i (3)
           , 0x0C
           , 0x01 --     br 1 (continue loop)
           , 0x0B --   end (if)
           , 0x0B -- end (loop)
           , 0x20
           , 0x04 -- local.get $sum
           , 0x0B -- end (func)
           ]

-- | Host Function Import module:
hostImportWasm :: ByteString
hostImportWasm =
  BS.pack $
    map fromIntegral $
      wasmHeader
        ++ [ -- Type section: 2 types (size 12 = 0x0C)
             0x01
           , 0x0C
           , 0x02
           , -- Type 0: (i32, i32) -> i32 [host_add]
             0x60
           , 0x02
           , 0x7F
           , 0x7F
           , 0x01
           , 0x7F
           , -- Type 1: (i32) -> i32 [host_callback, run_host_calls]
             0x60
           , 0x01
           , 0x7F
           , 0x01
           , 0x7F
           , -- Import section: 2 functions imported from "env" (size 36 = 0x24)
             0x02
           , 0x24
           , 0x02
           , -- env.host_add -> type 0
             0x03
           , 0x65
           , 0x6E
           , 0x76
           , 0x08
           , 0x68
           , 0x6F
           , 0x73
           , 0x74
           , 0x5F
           , 0x61
           , 0x64
           , 0x64
           , 0x00
           , 0x00
           , -- env.host_callback -> type 1
             0x03
           , 0x65
           , 0x6E
           , 0x76
           , 0x0D
           , 0x68
           , 0x6F
           , 0x73
           , 0x74
           , 0x5F
           , 0x63
           , 0x61
           , 0x6C
           , 0x6C
           , 0x62
           , 0x61
           , 0x63
           , 0x6B
           , 0x00
           , 0x01
           , -- Function section: 1 local function with type 1 (size 2 = 0x02)
             0x03
           , 0x02
           , 0x01
           , 0x01
           , -- Export section: "run_host_calls" -> func 2 (size 18 = 0x12)
             0x07
           , 0x12
           , 0x01
           , 0x0E
           , 0x72
           , 0x75
           , 0x6E
           , 0x5F
           , 0x68
           , 0x6F
           , 0x73
           , 0x74
           , 0x5F
           , 0x63
           , 0x61
           , 0x6C
           , 0x6C
           , 0x73
           , 0x00
           , 0x02
           , -- Code section: 1 function body (size 38 = 0x26)
             0x0A
           , 0x26
           , 0x01
           , -- body size: 36 bytes (0x24)
             0x24
           , 0x01
           , 0x02
           , 0x7F -- 2 local i32s: $i (local 1), $acc (local 2)
           , 0x03
           , 0x40 -- loop
           , 0x20
           , 0x01 --   local.get $i (1)
           , 0x20
           , 0x00 --   local.get $count (0)
           , 0x48 --   i32.lt_s
           , 0x04
           , 0x40 --   if
           , 0x20
           , 0x02 --     local.get $acc (2)
           , 0x20
           , 0x01 --     local.get $i (1)
           , 0x10
           , 0x01 --     call $host_callback (func 1)
           , 0x10
           , 0x00 --     call $host_add (func 0)
           , 0x21
           , 0x02 --     local.set $acc (2)
           , 0x20
           , 0x01 --     local.get $i (1)
           , 0x41
           , 0x01 --     i32.const 1
           , 0x6A --     i32.add
           , 0x21
           , 0x01 --     local.set $i (1)
           , 0x0C
           , 0x01 --     br 1
           , 0x0B --   end (if)
           , 0x0B -- end (loop)
           , 0x20
           , 0x02 -- local.get $acc
           , 0x0B -- end (func)
           ]

-- | Chaos & Fault Injection module:
chaosWasm :: ByteString
chaosWasm =
  BS.pack $
    map fromIntegral $
      wasmHeader
        ++ [ -- Type section: 2 types (size 9 = 0x09)
             0x01
           , 0x09
           , 0x02
           , -- Type 0: () -> () [trap_unreachable, infinite_loop]
             0x60
           , 0x00
           , 0x00
           , -- Type 1: (i32) -> i32 [div_by_zero, oob_memory_load]
             0x60
           , 0x01
           , 0x7F
           , 0x01
           , 0x7F
           , -- Function section: 4 functions (size 5 = 0x05)
             0x03
           , 0x05
           , 0x04
           , 0x00
           , 0x01
           , 0x01
           , 0x00
           , -- Memory section: 1 memory (size 4 = 0x04)
             0x05
           , 0x04
           , 0x01
           , 0x01
           , 0x01
           , 0x01
           , -- Export section: 5 exports (size 77 = 0x4D)
             0x07
           , 0x4D
           , 0x05
           , -- "memory" -> memory 0
             0x06
           , 0x6D
           , 0x65
           , 0x6D
           , 0x6F
           , 0x72
           , 0x79
           , 0x02
           , 0x00
           , -- "trap_unreachable" -> func 0
             0x10
           , 0x74
           , 0x72
           , 0x61
           , 0x70
           , 0x5F
           , 0x75
           , 0x6E
           , 0x72
           , 0x65
           , 0x61
           , 0x63
           , 0x68
           , 0x61
           , 0x62
           , 0x6C
           , 0x65
           , 0x00
           , 0x00
           , -- "div_by_zero" -> func 1
             0x0B
           , 0x64
           , 0x69
           , 0x76
           , 0x5F
           , 0x62
           , 0x79
           , 0x5F
           , 0x7A
           , 0x65
           , 0x72
           , 0x6F
           , 0x00
           , 0x01
           , -- "oob_memory_load" -> func 2
             0x0F
           , 0x6F
           , 0x6F
           , 0x62
           , 0x5F
           , 0x6D
           , 0x65
           , 0x6D
           , 0x6F
           , 0x72
           , 0x79
           , 0x5F
           , 0x6C
           , 0x6F
           , 0x61
           , 0x64
           , 0x00
           , 0x02
           , -- "infinite_loop" -> func 3
             0x0D
           , 0x69
           , 0x6E
           , 0x66
           , 0x69
           , 0x6E
           , 0x69
           , 0x74
           , 0x65
           , 0x5F
           , 0x6C
           , 0x6F
           , 0x6F
           , 0x70
           , 0x00
           , 0x03
           , -- Code section: 4 functions (size 29 = 0x1D)
             0x0A
           , 0x1D
           , 0x04
           , -- Func 0 (trap_unreachable): size 3
             0x03
           , 0x00
           , 0x00
           , 0x0B
           , -- Func 1 (div_by_zero): size 7
             0x07
           , 0x00
           , 0x20
           , 0x00
           , 0x41
           , 0x00
           , 0x6D
           , 0x0B
           , -- Func 2 (oob_memory_load): size 7
             0x07
           , 0x00
           , 0x20
           , 0x00
           , 0x28
           , 0x02
           , 0x00
           , 0x0B
           , -- Func 3 (infinite_loop): size 7
             0x07
           , 0x00
           , 0x03
           , 0x40
           , 0x0C
           , 0x00
           , 0x0B
           , 0x0B
           ]

-- | Bytecode with invalid magic header (tests rejection during validation)
corruptedMagicWasm :: ByteString
corruptedMagicWasm = BS.pack [0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x00, 0x00, 0x00]

-- | Bytecode with truncated / invalid section header
corruptedSectionWasm :: ByteString
corruptedSectionWasm =
  BS.pack $
    map fromIntegral $
      wasmHeader ++ [0x01, 0xFF, 0xFF]

{- | Caller introspection test guest:
Imports "caller_env"."inspect_caller" : (i32) -> i32
Exports "memory" (1 page)
Exports "test_caller" (param i32) (result i32) -> calls inspect_caller
-}
callerGuestWasm :: ByteString
callerGuestWasm =
  BS.pack $
    map fromIntegral $
      wasmHeader
        ++ [ -- 1. Type section: 1 type: (i32) -> i32
             0x01
           , 0x06
           , 0x01
           , 0x60
           , 0x01
           , 0x7F
           , 0x01
           , 0x7F
           , -- 2. Import section: "caller_env"."inspect_caller" -> type 0
             0x02
           , 0x1D
           , 0x01
           , 0x0A
           , 0x63
           , 0x61
           , 0x6C
           , 0x6C
           , 0x65
           , 0x72
           , 0x5F
           , 0x65
           , 0x6E
           , 0x76
           , 0x0E
           , 0x69
           , 0x6E
           , 0x73
           , 0x70
           , 0x65
           , 0x63
           , 0x74
           , 0x5F
           , 0x63
           , 0x61
           , 0x6C
           , 0x6C
           , 0x65
           , 0x72
           , 0x00
           , 0x00
           , -- 3. Function section: 1 local function using type 0
             0x03
           , 0x02
           , 0x01
           , 0x00
           , -- 5. Memory section: 1 memory, min=1 page
             0x05
           , 0x03
           , 0x01
           , 0x00
           , 0x01
           , -- 7. Export section: 2 exports ("memory" -> mem 0, "test_caller" -> func 1)
             0x07
           , 0x18
           , 0x02
           , 0x06
           , 0x6D
           , 0x65
           , 0x6D
           , 0x6F
           , 0x72
           , 0x79
           , 0x02
           , 0x00
           , 0x0B
           , 0x74
           , 0x65
           , 0x73
           , 0x74
           , 0x5F
           , 0x63
           , 0x61
           , 0x6C
           , 0x6C
           , 0x65
           , 0x72
           , 0x00
           , 0x01
           , -- 10. Code section: 1 function body (calls imported inspect_caller)
             0x0A
           , 0x08
           , 0x01
           , 0x06
           , 0x00
           , 0x20
           , 0x00
           , 0x10
           , 0x00
           , 0x0B
           ]
