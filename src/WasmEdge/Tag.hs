{- |
Module      : WasmEdge.Tag
Description : WasmEdge tag types and tag instances (Wasm exception handling proposal)
Copyright   : (c) wasmedge-hs contributors, 2026
License     : Apache-2.0
Stability   : stable

Supports the WebAssembly Exception Handling proposal (WasmEdge 0.18+):

* 'TagType' — describes the signature (parameter types) associated with an exception tag
* 'TagInstance' — a runtime tag instance retrieved from a module instance
-}
module WasmEdge.Tag
  ( -- * Tag type
    TagType (..)
  , getTagTypeFunctionType

    -- * Tag instance
  , TagInstance (..)
  , getTagInstanceType

    -- * Internal helpers
  , borrowTagType
  , borrowTagInstance
  , unsafeTagTypePtr
  , unsafeTagInstancePtr
  ) where

import Control.Exception (throwIO)
import Foreign.Ptr (Ptr, nullPtr)

import WasmEdge.Error
import WasmEdge.Function (FunctionType, borrowFunctionType)
import WasmEdge.Internal.FFI.Instance (c_TagInstanceGetTagType, c_TagTypeGetFunctionType)
import WasmEdge.Internal.Ownership (BorrowedCtx (..))
import WasmEdge.Internal.Types (TagInstanceTag, TagTypeTag)

-- ---------------------------------------------------------------------------
-- TagType
-- ---------------------------------------------------------------------------

{- | A WebAssembly tag type describing the parameter types of an exception tag.
Tag types are owned by the module / runtime and accessed via borrowed reference.
-}
newtype TagType = TagType (BorrowedCtx TagTypeTag)
  deriving stock (Eq)

-- | Retrieve the underlying 'FunctionType' describing this tag's payload types.
getTagTypeFunctionType :: TagType -> IO FunctionType
getTagTypeFunctionType (TagType (BorrowedCtx p)) = do
  ftPtr <- c_TagTypeGetFunctionType p
  if ftPtr == nullPtr
    then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_TagTypeGetFunctionType returned NULL"
    else borrowFunctionType ftPtr

-- ---------------------------------------------------------------------------
-- TagInstance
-- ---------------------------------------------------------------------------

-- | A runtime WebAssembly tag instance.
newtype TagInstance = TagInstance (BorrowedCtx TagInstanceTag)
  deriving stock (Eq)

-- | Get the 'TagType' of a 'TagInstance'.
getTagInstanceType :: TagInstance -> IO TagType
getTagInstanceType (TagInstance (BorrowedCtx p)) = do
  ttPtr <- c_TagInstanceGetTagType p
  if ttPtr == nullPtr
    then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_TagInstanceGetTagType returned NULL"
    else borrowTagType ttPtr

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

-- | Construct a borrowed 'TagType' from a raw pointer.
borrowTagType :: Ptr TagTypeTag -> IO TagType
borrowTagType p = pure (TagType (BorrowedCtx p))

-- | Construct a borrowed 'TagInstance' from a raw pointer.
borrowTagInstance :: Ptr TagInstanceTag -> IO TagInstance
borrowTagInstance p = pure (TagInstance (BorrowedCtx p))

-- | Extract the raw pointer from a 'TagType'.
unsafeTagTypePtr :: TagType -> Ptr TagTypeTag
unsafeTagTypePtr (TagType (BorrowedCtx p)) = p

-- | Extract the raw pointer from a 'TagInstance'.
unsafeTagInstancePtr :: TagInstance -> Ptr TagInstanceTag
unsafeTagInstancePtr (TagInstance (BorrowedCtx p)) = p
