-- |
-- Module      : WasmEdge.Internal.Ownership
-- Description : Owned and borrowed pointer wrappers with GC finalizer support
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : internal
--
-- This module implements the two fundamental pointer wrappers:
--
--   * 'OwnedCtx' — Haskell owns the resource; the GC will call the C delete
--     function via a 'ForeignPtr' finalizer if the Haskell object is collected.
--
--   * 'BorrowedCtx' — Haskell does not own the resource; no finalizer is
--     attached. The lifetime is guaranteed only by the caller.
--
-- The phantom type parameter @tag@ prevents mixing up different context types.
--
-- __Do not import this module in user code.__
module WasmEdge.Internal.Ownership
  ( -- * Owned contexts (Haskell owns, GC finalizes)
    OwnedCtx (..)
  , mkOwned
  , withOwned
  , touchOwned
    -- * Borrowed contexts (no ownership, no finalizer)
  , BorrowedCtx (..)
  , borrowCtx
  , withBorrowed
    -- * Unsafe coercions (internal use only)
  , unsafeBorrowOwned
  , unsafeOwnedPtr
  ) where

import Foreign.Ptr          (Ptr, nullPtr)
import Foreign.ForeignPtr   (ForeignPtr, newForeignPtr, withForeignPtr,
                              touchForeignPtr, unsafeForeignPtrToPtr)
import qualified Foreign.Concurrent as FC

-- ---------------------------------------------------------------------------
-- OwnedCtx
-- ---------------------------------------------------------------------------

-- | An @'OwnedCtx' tag@ holds a 'ForeignPtr' with a C delete function
-- attached as a GC finalizer.
--
-- The finalizer is called exactly once, either when:
--
--   1. The explicit @delete*@ function is called (via 'withOwned'), or
--   2. The 'ForeignPtr' is garbage-collected.
--
-- In practice, prefer explicit cleanup with @with*@ bracket functions.
newtype OwnedCtx tag = OwnedCtx { unOwnedCtx :: ForeignPtr tag }
  deriving stock (Eq)

-- | Create an 'OwnedCtx' from a raw 'Ptr' and an IO action to call when
-- the pointer is no longer needed (the delete function).
--
-- If the pointer is 'nullPtr', the delete action is /not/ registered and
-- the resulting 'OwnedCtx' wraps a null foreign pointer.
mkOwned :: (Ptr tag -> IO ()) -- ^ delete / finalize action
        -> Ptr tag
        -> IO (OwnedCtx tag)
mkOwned finalizer ptr
  | ptr == nullPtr = do
      fp <- newForeignPtr (error "mkOwned: null delete fn") ptr
      pure (OwnedCtx fp)
  | otherwise = do
      fp <- FC.newForeignPtr ptr (finalizer ptr)
      pure (OwnedCtx fp)

-- | Run an IO action with the underlying 'Ptr' of an 'OwnedCtx'.
-- The 'OwnedCtx' is kept alive for the duration of the action.
withOwned :: OwnedCtx tag -> (Ptr tag -> IO a) -> IO a
withOwned (OwnedCtx fp) = withForeignPtr fp
{-# INLINE withOwned #-}

-- | Ensure an 'OwnedCtx' is kept alive up to this point in a sequence of
-- IO actions. Use when passing the underlying pointer to a C function that
-- does not keep a reference, and you need GHC not to collect the object early.
touchOwned :: OwnedCtx tag -> IO ()
touchOwned (OwnedCtx fp) = touchForeignPtr fp
{-# INLINE touchOwned #-}

-- ---------------------------------------------------------------------------
-- BorrowedCtx
-- ---------------------------------------------------------------------------

-- | A @'BorrowedCtx' tag@ is a non-owning reference to a C context.
-- It carries /no/ finalizer. The caller must guarantee that the underlying
-- C object outlives any use of this 'BorrowedCtx'.
newtype BorrowedCtx tag = BorrowedCtx { unBorrowedCtx :: Ptr tag }
  deriving stock (Eq)

-- | Borrow an 'OwnedCtx': extract a non-owning 'BorrowedCtx'.
-- The 'OwnedCtx' must remain alive as long as the 'BorrowedCtx' is used.
borrowCtx :: OwnedCtx tag -> BorrowedCtx tag
borrowCtx (OwnedCtx fp) = BorrowedCtx (unsafeForeignPtrToPtr fp)
{-# INLINE borrowCtx #-}

-- | Run an IO action with the underlying 'Ptr' of a 'BorrowedCtx'.
withBorrowed :: BorrowedCtx tag -> (Ptr tag -> IO a) -> IO a
withBorrowed (BorrowedCtx p) f = f p
{-# INLINE withBorrowed #-}

-- ---------------------------------------------------------------------------
-- Unsafe utilities (internal only)
-- ---------------------------------------------------------------------------

-- | /Unsafe/: extract a 'BorrowedCtx' from an 'OwnedCtx' without
-- keeping the owner alive. Use only when the caller guarantees lifetime.
unsafeBorrowOwned :: OwnedCtx tag -> BorrowedCtx tag
unsafeBorrowOwned = borrowCtx
{-# INLINE unsafeBorrowOwned #-}

-- | /Unsafe/: extract the raw 'Ptr' from an 'OwnedCtx'.
-- The 'ForeignPtr' may be GC'd after this call.
unsafeOwnedPtr :: OwnedCtx tag -> Ptr tag
unsafeOwnedPtr (OwnedCtx fp) = unsafeForeignPtrToPtr fp
{-# INLINE unsafeOwnedPtr #-}
