{- |
Module      : WasmEdge.Async
Description : Asynchronous WasmEdge execution results
Copyright   : (c) wasmedge-hs contributors, 2026
License     : Apache-2.0
Stability   : stable

When functions are invoked via @async*@ variants in 'WasmEdge.VM' or
'WasmEdge.Executor', they return an 'Async' handle that can be waited on.
-}
module WasmEdge.Async
  ( Async (..)
  , wait
  , waitFor
  , cancel
  , getReturnsLength
  , getReturns
  -- Internal
  , mkAsync
  , borrowAsync
  ) where

import Control.Exception (throwIO)
import Data.Word (Word32, Word64)
import Foreign.C (CBool (..))
import Foreign.Ptr

import WasmEdge.Error
import WasmEdge.Internal.FFI.Execution
import WasmEdge.Internal.Ownership
import WasmEdge.Internal.Storable
import WasmEdge.Internal.Types
import WasmEdge.Internal.Utils (checkResult)
import WasmEdge.Types
import WasmEdge.Value (peekValArray)

-- | An asynchronous execution result handle.
newtype Async = Async (OwnedCtx AsyncTag)

-- | Create an 'Async' from a raw pointer (used by VM / Executor).
mkAsync :: Ptr AsyncTag -> IO Async
mkAsync p
  | p == nullPtr = throwIO $ WasmEdgeError ErrCategory_WASM 0 "Async returned NULL"
  | otherwise = Async <$> mkOwned (appFunPtr c_AsyncDelete) p

-- | Create a borrowed 'Async' handle from a raw pointer (does not finalize).
borrowAsync :: Ptr AsyncTag -> IO Async
borrowAsync p = Async <$> mkOwned (\_ -> pure ()) p

-- | Block until the async result is ready.
wait :: Async -> IO ()
wait (Async o) = withOwned o c_AsyncWait

-- | Wait up to @timeout@ milliseconds. Returns 'True' if the result is ready.
waitFor :: Async -> Word64 -> IO Bool
waitFor (Async o) ms = withOwned o $ \p -> do
  CBool b <- c_AsyncWaitFor p ms
  pure (b /= 0)

-- | Cancel the async operation.
cancel :: Async -> IO ()
cancel (Async o) = withOwned o c_AsyncCancel

-- | Get the number of return values.
getReturnsLength :: Async -> IO Word32
getReturnsLength (Async o) = withOwned o c_AsyncGetReturnsLength

-- | Wait for the result and retrieve the return values.
getReturns :: Async -> IO (WasmResult [WasmVal])
getReturns (Async o) = withOwned o $ \aPtr -> do
  n <- c_AsyncGetReturnsLength aPtr
  allocaCResult $ \resPtr ->
    withCValueArray (fromIntegral n) $ \retsPtr -> do
      c_AsyncGet resPtr aPtr (castPtr retsPtr) n
      r <- checkResult resPtr
      case r of
        Left err -> pure (Left err)
        Right () -> Right <$> peekValArray (castPtr retsPtr) n

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr = mkDeleter

foreign import ccall "dynamic" mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
