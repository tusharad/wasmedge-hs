{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : WasmEdge.Function.Memory
Description : Memory-aware host function lifting
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Provides utilities for writing host functions that work with complex Haskell
types by automatically marshalling them through Wasm linear memory.

== The problem

WebAssembly functions can only pass numeric values (@i32@, @i64@, @f32@, @f64@)
across the FFI boundary. To call a host function with a @Text@ argument or
return a @[Double]@, the convention is:

  * The guest writes the data into its linear memory.
  * The guest passes the @(ptr: i32, len: i32)@ pair as function arguments.
  * The host reads the bytes from the calling frame's memory and deserialises.

'liftMemFunc' automates this entire read-deserialise-compute-serialise-write
pipeline for host functions.

== Usage

@
-- A host function that takes Text input and returns Text output:
myGreeter :: Text -> IO (Either WasmEdgeError Text)
myGreeter name = pure (Right (\"Hello, \" \<\> name \<\> \"!\"))

-- Register it as a host function with signature (i32, i32) -> i64:
fn \<- liftMemFunc myGreeter
withFunction someType fn $ \\hostFn -> ...
@

The Wasm guest calls it as:
@
let ptr = alloc(len);
store_str(ptr, input_str);
let result_packed = greet(ptr, len);
let ret_ptr = (result_packed >> 32) as i32;
let ret_len = (result_packed & 0xFFFFFFFF) as i32;
@

== Result encoding

Return values are packed as a single @i64@: upper 32 bits = output pointer,
lower 32 bits = output length. The output buffer is written into a scratch
region of Wasm linear memory.

For host functions that do not return data (only side effects), use
'liftMemFunc_'.
-}
module WasmEdge.Function.Memory
  ( -- * Lifting host functions
    liftMemFunc
  , liftMemFunc_
  , liftMemFuncWith

    -- * Helper: get memory from calling frame
  , callingFrameMemory
  ) where

import Data.Bits (shiftL, (.|.))
import Data.Word (Word32, Word64)
import Foreign.Ptr (nullPtr)

import WasmEdge.Error (ErrCategory (..), WasmEdgeError (..), WasmResult)
import WasmEdge.Function (CallingFrame, callingFrameGetMemoryInstance)
import WasmEdge.Memory (MemoryInstance, borrowMemory)
import WasmEdge.Memory.Alloc (AllocConvention (..))
import WasmEdge.Memory.Codec (WasmMemory (..))
import WasmEdge.Types (WasmVal (..))
import WasmEdge.VM (VM)

-- ---------------------------------------------------------------------------
-- Calling-frame memory helper
-- ---------------------------------------------------------------------------

{- | Get the linear memory instance from a 'CallingFrame'.

The calling frame always has memory index 0 available if the guest module
declares linear memory, which all practical Wasm modules do.

Returns 'Left' if no linear memory is available (null pointer from C API).
-}
callingFrameMemory :: CallingFrame -> IO (WasmResult MemoryInstance)
callingFrameMemory frame = do
  ptr <- callingFrameGetMemoryInstance frame 0
  if ptr == nullPtr
    then
      pure
        ( Left
            ( WasmEdgeError
                ErrCategory_UserDefined
                30
                "callingFrameMemory: no linear memory at index 0 in calling frame"
            )
        )
    else Right <$> borrowMemory ptr

-- ---------------------------------------------------------------------------
-- Core lifting
-- ---------------------------------------------------------------------------

{- | Lift a Haskell function @a -> IO (Either WasmEdgeError b)@ into a raw
'HostFunc' that marshals arguments through Wasm linear memory.

The generated host function:

* Expects two @i32@ arguments: @(ptr, len)@ — the pointer and length of the
  input buffer in Wasm linear memory.
* Reads and deserialises @a@ from that buffer using 'wasmPeek'.
* Runs the user function.
* Serialises @b@ into a scratch region of Wasm linear memory at 1 MiB offset.
* Returns a single @i64@ with @(retPtr \<\< 32 | retLen)@.

The function type to register with 'createFunction' is @[I32, I32] -> [I64]@.

__Note__: The scratch-region approach works for output up to ~63 MiB. For
larger outputs or when the Wasm module manages its own heap, use
'liftMemFuncWith' instead.
-}
liftMemFunc ::
  forall a b.
  (WasmMemory a, WasmMemory b) =>
  -- | The Haskell function to lift
  (a -> IO (Either WasmEdgeError b)) ->
  (CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal]))
liftMemFunc f frame args =
  case args of
    [WasmI32 inPtr, WasmI32 inLen] -> do
      memResult <- callingFrameMemory frame
      case memResult of
        Left err -> pure (Left err)
        Right mem -> do
          peekResult <- wasmPeek mem (fromIntegral inPtr) (fromIntegral inLen)
          case peekResult of
            Left err -> pure (Left err)
            Right a -> do
              result <- f a
              case result of
                Left err -> pure (Left err)
                Right b -> do
                  -- Write output to a well-known scratch region (1 MiB offset)
                  let scratchBase = 1048576 :: Word32 -- 1 MiB
                  pokeResult <- wasmPoke mem scratchBase b
                  case pokeResult of
                    Left err -> pure (Left err)
                    Right outLen ->
                      let packed :: Word64
                          packed =
                            (fromIntegral scratchBase `shiftL` 32)
                              .|. fromIntegral outLen
                       in pure (Right [WasmI64 (fromIntegral packed)])
    _ ->
      pure
        ( Left
            ( WasmEdgeError
                ErrCategory_UserDefined
                31
                "liftMemFunc: expected exactly two i32 arguments (ptr, len)"
            )
        )

{- | Like 'liftMemFunc' but for functions with no return value (pure side-effects).

The generated host function returns no values.
The function type for 'createFunction' is @[I32, I32] -> []@.
-}
liftMemFunc_ ::
  forall a.
  (WasmMemory a) =>
  (a -> IO (Either WasmEdgeError ())) ->
  (CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal]))
liftMemFunc_ f frame args =
  case args of
    [WasmI32 inPtr, WasmI32 inLen] -> do
      memResult <- callingFrameMemory frame
      case memResult of
        Left err -> pure (Left err)
        Right mem -> do
          peekResult <- wasmPeek mem (fromIntegral inPtr) (fromIntegral inLen)
          case peekResult of
            Left err -> pure (Left err)
            Right a -> do
              result <- f a
              case result of
                Left err -> pure (Left err)
                Right () -> pure (Right [])
    _ ->
      pure
        ( Left
            ( WasmEdgeError
                ErrCategory_UserDefined
                31
                "liftMemFunc_: expected exactly two i32 arguments (ptr, len)"
            )
        )

{- | Advanced variant of 'liftMemFunc' that uses the 'AllocConvention' to
call the guest's @alloc@ exports for output buffer management.

This is the production-grade approach: the guest controls the heap, and the
host simply writes the output wherever @alloc@ says. The 'VM' reference is
needed to call back into the guest's @alloc@ export.

The generated host function signature is @[I32, I32] -> [I64]@ (same as
'liftMemFunc').

__Current implementation__: delegates to 'liftMemFunc' (fixed scratch region).
A future version will call @alloc@ via the VM inside the host callback.
-}
liftMemFuncWith ::
  forall a b.
  (WasmMemory a, WasmMemory b) =>
  -- | The VM (reserved for future use: calling guest @alloc@)
  VM ->
  -- | Module name (reserved for future use)
  String ->
  -- | Reserved for future use
  AllocConvention ->
  (a -> IO (Either WasmEdgeError b)) ->
  (CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal]))
liftMemFuncWith _vm _modName _conv = liftMemFunc
