{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : WasmEdge.Memory.Alloc
Description : High-level bracket for Wasm-side memory allocation and data marshalling
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Provides a high-level API for calling WebAssembly functions that accept or
return heap-allocated data. This module implements the standard __guest-side
allocation__ convention:

1. The Wasm guest module exports:
   * @alloc(size: i32) -> i32@   — allocate @size@ bytes, return pointer
   * @dealloc(ptr: i32, len: i32)@ — free a previously allocated buffer

2. The Haskell host serialises the input with 'WasmEdge.Memory.Codec.wasmPoke',
   calls the Wasm function with @(ptr, len)@, and deserialises the output.

This convention is compatible with the allocator produced by Rust's
@#[no_mangle] pub fn alloc(size: usize) -> *mut u8@ pattern and with
the @wasmedge-sdk@ Rust examples in this repository.

== Quick start

@
-- Register the module first:
registerModuleFromFile vm "my_module" "my_module.wasm" >>= throwOnFail

-- Then call a function that takes Text (ptr, len) and returns Text (ptr, len):
result \<- withWasmBuffer vm "my_module" "greet" defaultConvention ("Hello" :: Text)
case result of
  Left err  -> print err
  Right txt -> putStrLn txt
@

See 'withWasmBuffer2' for two-argument variants.

== Return value encoding

The Wasm function must return a @(ptr: i32, len: i32)@ pair. We support two
common encodings:

* 'PackedI64' — packed into a single @i64@: @ptr \<\< 32 | len@. This is
  allocation-free on the guest side.
* 'SeparateI32s' — two separate @i32@ return values.
-}
module WasmEdge.Memory.Alloc
  ( -- * High-level buffer call (single argument)
    withWasmBuffer

    -- * High-level buffer call (two arguments)
  , withWasmBuffer2

    -- * Manual allocation primitives
  , wasmAlloc
  , wasmDealloc

    -- * Convention configuration
  , AllocConvention (..)
  , ResultEncoding (..)
  , defaultConvention

    -- * Type aliases
  , ModuleName
  , FunctionName
  ) where

import Data.Bits (shiftR, (.&.))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32, Word64)

import WasmEdge.Error (ErrCategory (..), WasmEdgeError (..), WasmResult)
import WasmEdge.Memory (MemoryInstance)
import WasmEdge.Memory.Codec (WasmMemory (..), wasmPeek, wasmPoke)
import WasmEdge.Module (findMemory)
import WasmEdge.Store (findModule)
import WasmEdge.Types (WasmVal (..))
import WasmEdge.VM (VM, executeRegistered, getStore)

-- ---------------------------------------------------------------------------
-- Type aliases
-- ---------------------------------------------------------------------------

-- | Name of the registered Wasm module.
type ModuleName = Text

-- | Name of the exported Wasm function.
type FunctionName = Text

-- ---------------------------------------------------------------------------
-- Convention
-- ---------------------------------------------------------------------------

-- | Configuration for the guest allocator naming convention.
data AllocConvention = AllocConvention
  { allocFunc :: FunctionName
  {- ^ Name of the allocator export. Default: @\"alloc\"@.
  Expected signature: @(i32 size) -> i32 ptr@
  -}
  , deallocFunc :: FunctionName
  {- ^ Name of the deallocator export. Default: @\"dealloc\"@.
  Expected signature: @(i32 ptr, i32 len)@
  -}
  , resultEncoding :: ResultEncoding
  -- ^ How the called Wasm function returns a @(ptr, len)@ result.
  , scratchSize :: Word32
  -- ^ Scratch buffer size in bytes allocated for each call. Default: 65536 (64 KiB).
  }

{- | How a Wasm function encodes its buffer result.

Most idiomatic Rust guest code uses 'PackedI64'. @wasm-bindgen@ uses
'SeparateI32s'.
-}
data ResultEncoding
  = {- | @ptr@ packed into upper 32 bits, @len@ in lower 32 bits of a single @i64@.
    Guest: @return ((ptr as i64) << 32) | (len as i64)@
    -}
    PackedI64
  | -- | Two separate @i32@ return values: @[WasmI32 ptr, WasmI32 len]@.
    SeparateI32s

-- | The default convention: @alloc@, @dealloc@, packed i64 result, 64 KiB scratch.
defaultConvention :: AllocConvention
defaultConvention =
  AllocConvention
    { allocFunc = "alloc"
    , deallocFunc = "dealloc"
    , resultEncoding = PackedI64
    , scratchSize = 65536
    }

-- ---------------------------------------------------------------------------
-- Manual allocation primitives
-- ---------------------------------------------------------------------------

{- | Allocate @n@ bytes inside a Wasm module's linear memory by calling the
module-exported @alloc@ function.

Returns the pointer (as 'Word32') on success, or 'Left' on failure.
-}
wasmAlloc ::
  VM ->
  ModuleName ->
  AllocConvention ->
  -- | Number of bytes to allocate
  Word32 ->
  IO (WasmResult Word32)
wasmAlloc vm modName conv sz = do
  res <- executeRegistered vm modName (allocFunc conv) [WasmI32 (fromIntegral sz)]
  pure $ case res of
    Left err -> Left err
    Right [WasmI32 ptr] -> Right (fromIntegral ptr)
    Right _ ->
      Left
        ( WasmEdgeError
            ErrCategory_UserDefined
            20
            "wasmAlloc: unexpected return value from alloc function (expected i32 pointer)"
        )

{- | Free a previously-allocated Wasm buffer by calling the module-exported
@dealloc@ function.
-}
wasmDealloc ::
  VM ->
  ModuleName ->
  AllocConvention ->
  -- | Pointer returned by 'wasmAlloc'
  Word32 ->
  -- | Length in bytes
  Word32 ->
  IO (WasmResult ())
wasmDealloc vm modName conv ptr len = do
  res <-
    executeRegistered
      vm
      modName
      (deallocFunc conv)
      [WasmI32 (fromIntegral ptr), WasmI32 (fromIntegral len)]
  pure $ case res of
    Left err -> Left err
    Right _ -> Right ()

-- ---------------------------------------------------------------------------
-- Memory lookup
-- ---------------------------------------------------------------------------

{- | Get the first (index-0) linear memory of a registered Wasm module.

Uses the VM's 'Store' → 'ModuleInstance' → 'findMemory' chain.
-}
getModuleMemory :: VM -> ModuleName -> IO (WasmResult MemoryInstance)
getModuleMemory vm modName = do
  store <- getStore vm
  mMod <- findModule store modName
  case mMod of
    Nothing ->
      pure
        ( Left
            ( WasmEdgeError
                ErrCategory_UserDefined
                22
                ("getModuleMemory: module not found: " <> modName)
            )
        )
    Just modInst -> do
      mMem <- findMemory modInst "memory"
      case mMem of
        Just mem -> pure (Right mem)
        Nothing ->
          -- Try unnamed / default memory (some modules export with no name)
          pure
            ( Left
                ( WasmEdgeError
                    ErrCategory_UserDefined
                    23
                    ( "getModuleMemory: no memory named 'memory' in module '"
                        <> modName
                        <> "'. Ensure your Wasm module exports linear memory as \"memory\"."
                    )
                )
            )

-- ---------------------------------------------------------------------------
-- High-level bracket: single argument
-- ---------------------------------------------------------------------------

{- | The primary high-level API for calling a Wasm function that takes a
serialised buffer and returns a serialised buffer.

The Wasm function must have the signature (depending on 'ResultEncoding'):

* 'PackedI64':  @(ptr: i32, len: i32) -> i64@
* 'SeparateI32s': @(ptr: i32, len: i32) -> (i32, i32)@

Internally, this bracket:

1. Allocates a scratch buffer in Wasm linear memory via the @alloc@ export.
2. Serialises the input @a@ into that buffer using 'wasmPoke'.
3. Calls the Wasm function with @(inputPtr, inputLen)@.
4. Decodes the return value as @(retPtr, retLen)@.
5. Reads and deserialises @b@ from Wasm memory at @(retPtr, retLen)@.
6. Deallocates both the input and output buffers via @dealloc@.

Returns 'Left' if any step fails. Deallocation is attempted on all error
paths.
-}
withWasmBuffer ::
  forall a b.
  (WasmMemory a, WasmMemory b) =>
  VM ->
  ModuleName ->
  FunctionName ->
  AllocConvention ->
  -- | Input value to serialise
  a ->
  IO (WasmResult b)
withWasmBuffer vm modName fnName conv input = do
  let sz = scratchSize conv
  -- Step 1: allocate scratch buffer
  allocResult <- wasmAlloc vm modName conv sz
  case allocResult of
    Left err -> pure (Left err)
    Right inputPtr -> do
      -- Step 2: get memory instance
      memResult <- getModuleMemory vm modName
      case memResult of
        Left err -> do
          _ <- wasmDealloc vm modName conv inputPtr sz
          pure (Left err)
        Right mem -> do
          -- Step 3: serialise input
          pokeResult <- wasmPoke mem inputPtr input
          case pokeResult of
            Left err -> do
              _ <- wasmDealloc vm modName conv inputPtr sz
              pure (Left err)
            Right inputLen -> do
              -- Step 4: call the Wasm function
              callResult <-
                executeRegistered
                  vm
                  modName
                  fnName
                  [WasmI32 (fromIntegral inputPtr), WasmI32 (fromIntegral inputLen)]
              -- Step 5: free input buffer (best-effort)
              _ <- wasmDealloc vm modName conv inputPtr sz
              case callResult of
                Left err -> pure (Left err)
                Right retVals ->
                  case decodeResult (resultEncoding conv) retVals of
                    Left err -> pure (Left err)
                    Right (retPtr, retLen) -> do
                      -- Step 6: deserialise output
                      result <- wasmPeek mem retPtr retLen
                      -- Step 7: free output buffer (best-effort)
                      _ <- wasmDealloc vm modName conv retPtr retLen
                      pure result

-- ---------------------------------------------------------------------------
-- High-level bracket: two arguments
-- ---------------------------------------------------------------------------

{- | Like 'withWasmBuffer' but for Wasm functions that take two buffer
arguments.

Expected Wasm signature (@'PackedI64'@):

@(aPtr: i32, aLen: i32, bPtr: i32, bLen: i32) -> i64@
-}
withWasmBuffer2 ::
  forall a b c.
  (WasmMemory a, WasmMemory b, WasmMemory c) =>
  VM ->
  ModuleName ->
  FunctionName ->
  AllocConvention ->
  a ->
  b ->
  IO (WasmResult c)
withWasmBuffer2 vm modName fnName conv inputA inputB = do
  let sz = scratchSize conv
  allocA <- wasmAlloc vm modName conv sz
  case allocA of
    Left err -> pure (Left err)
    Right ptrA -> do
      allocB <- wasmAlloc vm modName conv sz
      case allocB of
        Left err -> do
          _ <- wasmDealloc vm modName conv ptrA sz
          pure (Left err)
        Right ptrB -> do
          memResult <- getModuleMemory vm modName
          case memResult of
            Left err -> do
              _ <- wasmDealloc vm modName conv ptrA sz
              _ <- wasmDealloc vm modName conv ptrB sz
              pure (Left err)
            Right mem -> do
              rA <- wasmPoke mem ptrA inputA
              rB <- wasmPoke mem ptrB inputB
              case (rA, rB) of
                (Left err, _) -> do
                  _ <- wasmDealloc vm modName conv ptrA sz
                  _ <- wasmDealloc vm modName conv ptrB sz
                  pure (Left err)
                (_, Left err) -> do
                  _ <- wasmDealloc vm modName conv ptrA sz
                  _ <- wasmDealloc vm modName conv ptrB sz
                  pure (Left err)
                (Right lenA, Right lenB) -> do
                  callResult <-
                    executeRegistered
                      vm
                      modName
                      fnName
                      [ WasmI32 (fromIntegral ptrA)
                      , WasmI32 (fromIntegral lenA)
                      , WasmI32 (fromIntegral ptrB)
                      , WasmI32 (fromIntegral lenB)
                      ]
                  _ <- wasmDealloc vm modName conv ptrA sz
                  _ <- wasmDealloc vm modName conv ptrB sz
                  case callResult of
                    Left err -> pure (Left err)
                    Right retVals ->
                      case decodeResult (resultEncoding conv) retVals of
                        Left err -> pure (Left err)
                        Right (retPtr, retLen) -> do
                          result <- wasmPeek mem retPtr retLen
                          _ <- wasmDealloc vm modName conv retPtr retLen
                          pure result

-- ---------------------------------------------------------------------------
-- Internal: decode (ptr, len) from Wasm return values
-- ---------------------------------------------------------------------------

decodeResult :: ResultEncoding -> [WasmVal] -> WasmResult (Word32, Word32)
decodeResult PackedI64 [WasmI64 packed] =
  let ptr = fromIntegral ((fromIntegral packed :: Word64) `shiftR` 32) :: Word32
      len = fromIntegral ((fromIntegral packed :: Word64) .&. 0xFFFFFFFF) :: Word32
   in Right (ptr, len)
decodeResult SeparateI32s [WasmI32 ptr, WasmI32 len] =
  Right (fromIntegral ptr, fromIntegral len)
decodeResult enc vals =
  Left
    ( WasmEdgeError
        ErrCategory_UserDefined
        21
        ( "withWasmBuffer: unexpected return values from Wasm function. "
            <> "Got "
            <> showVals vals
            <> ". Expected "
            <> case enc of
              PackedI64 -> "a single i64 (packed ptr<<32|len)"
              SeparateI32s -> "two i32 values [ptr, len]"
        )
    )

showVals :: [WasmVal] -> Text
showVals [] = "[]"
showVals vs = "[" <> go vs <> "]"
  where
    go [] = ""
    go [v] = showVal v
    go (v : rest) = showVal v <> ", " <> go rest
    showVal (WasmI32 n) = "i32:" <> showT n
    showVal (WasmI64 n) = "i64:" <> showT n
    showVal _ = "?"
    showT :: (Show a) => a -> Text
    showT = T.pack . show
