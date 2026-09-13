{- |
Module      : WasmEdge.Internal.Ownership
Description : Owned and borrowed pointer wrappers with GC finalizer support
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : internal

This module implements the two fundamental pointer wrappers:

  * 'OwnedCtx' — Haskell owns the resource; the GC will call the C delete
    function via a 'ForeignPtr' finalizer if the Haskell object is collected.

  * 'BorrowedCtx' — Haskell does not own the resource; no finalizer is
    attached. The lifetime is guaranteed only by the caller.

The phantom type parameter @tag@ prevents mixing up different context types.

__Do not import this module in user code.__
-}
module WasmEdge.Internal.Ownership
  ( -- * Owned contexts (Haskell owns, GC finalizes)
    OwnedCtx (..)
  , mkOwned
  , withOwned
  , touchOwned
  , finalizeOwned
  , disarmOwned

    -- * Borrowed contexts (no ownership, no finalizer)
  , BorrowedCtx (..)
  , borrowCtx
  , withBorrowed

    -- * Unsafe coercions (internal use only)
  , unsafeBorrowOwned
  , unsafeOwnedPtr
  ) where

import Control.Monad (unless)
import Data.IORef (newIORef, readIORef, writeIORef)
import Foreign.Concurrent qualified as FC
import Foreign.ForeignPtr
  ( ForeignPtr
  , finalizeForeignPtr
  , newForeignPtr_
  , touchForeignPtr
  , withForeignPtr
  )
import Foreign.ForeignPtr.Unsafe (unsafeForeignPtrToPtr)
import Foreign.Ptr (Ptr, nullPtr)

-- ---------------------------------------------------------------------------
-- OwnedCtx
-- ---------------------------------------------------------------------------

{- | An @'OwnedCtx' tag@ holds a 'ForeignPtr' with a C delete function
attached as a GC finalizer.

The finalizer is called exactly once, either when:

  1. The explicit @delete*@ function is called (via 'finalizeOwned'), or
  2. The 'ForeignPtr' is garbage-collected.

In practice, prefer explicit cleanup with @with*@ bracket functions.
-}
data OwnedCtx tag = OwnedCtx
  { unOwnedCtx :: !(ForeignPtr tag)
  , disarmAction :: !(IO ())
  }

instance Eq (OwnedCtx tag) where
  OwnedCtx fp1 _ == OwnedCtx fp2 _ = fp1 == fp2

{- | Create an 'OwnedCtx' from a raw 'Ptr' and an IO action to call when
the pointer is no longer needed (the delete function).

If the pointer is 'nullPtr', the delete action is /not/ registered and
the resulting 'OwnedCtx' wraps a null foreign pointer.
-}
mkOwned ::
  -- | delete / finalize action
  (Ptr tag -> IO ()) ->
  Ptr tag ->
  IO (OwnedCtx tag)
mkOwned finalizer ptr
  | ptr == nullPtr = do
      fp <- newForeignPtr_ ptr
      pure (OwnedCtx fp (pure ()))
  | otherwise = do
      disarmedRef <- newIORef False
      fp <- FC.newForeignPtr ptr $ do
        disarmed <- readIORef disarmedRef
        unless disarmed (finalizer ptr)
      pure (OwnedCtx fp (writeIORef disarmedRef True))

{- | Run an IO action with the underlying 'Ptr' of an 'OwnedCtx'.
The 'OwnedCtx' is kept alive for the duration of the action.
-}
withOwned :: OwnedCtx tag -> (Ptr tag -> IO a) -> IO a
withOwned (OwnedCtx fp _) = withForeignPtr fp
{-# INLINE withOwned #-}

{- | Ensure an 'OwnedCtx' is kept alive up to this point in a sequence of
IO actions. Use when passing the underlying pointer to a C function that
does not keep a reference, and you need GHC not to collect the object early.
-}
touchOwned :: OwnedCtx tag -> IO ()
touchOwned (OwnedCtx fp _) = touchForeignPtr fp
{-# INLINE touchOwned #-}

{- | Explicitly finalize an 'OwnedCtx', running its cleanup action immediately
and disabling future GC finalization.
-}
finalizeOwned :: OwnedCtx tag -> IO ()
finalizeOwned (OwnedCtx fp _) = finalizeForeignPtr fp
{-# INLINE finalizeOwned #-}

{- | Disarm the finalizer of an 'OwnedCtx' when ownership has been transferred
to a C container (e.g. adding a function/table/memory/global to a ModuleInstance).
-}
disarmOwned :: OwnedCtx tag -> IO ()
disarmOwned (OwnedCtx _ act) = act
{-# INLINE disarmOwned #-}

-- ---------------------------------------------------------------------------
-- BorrowedCtx
-- ---------------------------------------------------------------------------

{- | A @'BorrowedCtx' tag@ is a non-owning reference to a C context.
It carries /no/ finalizer. The caller must guarantee that the underlying
C object outlives any use of this 'BorrowedCtx'.
-}
newtype BorrowedCtx tag = BorrowedCtx {unBorrowedCtx :: Ptr tag}
  deriving stock (Eq)

{- | Borrow an 'OwnedCtx': extract a non-owning 'BorrowedCtx'.
The 'OwnedCtx' must remain alive as long as the 'BorrowedCtx' is used.
-}
borrowCtx :: OwnedCtx tag -> BorrowedCtx tag
borrowCtx (OwnedCtx fp _) = BorrowedCtx (unsafeForeignPtrToPtr fp)
{-# INLINE borrowCtx #-}

-- | Run an IO action with the underlying 'Ptr' of a 'BorrowedCtx'.
withBorrowed :: BorrowedCtx tag -> (Ptr tag -> IO a) -> IO a
withBorrowed (BorrowedCtx p) f = f p
{-# INLINE withBorrowed #-}

-- ---------------------------------------------------------------------------
-- Unsafe utilities (internal only)
-- ---------------------------------------------------------------------------

{- | /Unsafe/: extract a 'BorrowedCtx' from an 'OwnedCtx' without
keeping the owner alive. Use only when the caller guarantees lifetime.
-}
unsafeBorrowOwned :: OwnedCtx tag -> BorrowedCtx tag
unsafeBorrowOwned = borrowCtx
{-# INLINE unsafeBorrowOwned #-}

{- | /Unsafe/: extract the raw 'Ptr' from an 'OwnedCtx'.
The 'ForeignPtr' may be GC'd after this call.
-}
unsafeOwnedPtr :: OwnedCtx tag -> Ptr tag
unsafeOwnedPtr (OwnedCtx fp _) = unsafeForeignPtrToPtr fp
{-# INLINE unsafeOwnedPtr #-}
