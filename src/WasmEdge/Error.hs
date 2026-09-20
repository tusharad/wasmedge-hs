{- |
Module      : WasmEdge.Error
Description : WasmEdge error types and exception hierarchy
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : stable

This module defines 'WasmEdgeError', the exception type thrown by all
operations that fail in the WasmEdge C runtime. It also provides the
'ErrCategory' and 'ErrCode' types that mirror the C API enums.

Most users only need to catch 'WasmEdgeError' in an exception handler:

@
result <- try (runWasmFile vm "module.wasm" "main" []) :: IO (Either WasmEdgeError [WasmVal])
@
-}
module WasmEdge.Error
  ( -- * Error type
    WasmEdgeError (..)
  , WasmResult

    -- * Error category
  , ErrCategory (..)
  , mkErrCategory

    -- * Common predicates
  , isSuccess
  , isUserError
  , formatError

    -- * Convenience
  , throwOnLeft
  ) where

import Control.DeepSeq (NFData)
import Control.Exception (Exception, throwIO)
import Data.Text (Text)
import Data.Word (Word32)
import GHC.Generics (Generic)
import Numeric (showHex)

-- ---------------------------------------------------------------------------
-- Error category
-- ---------------------------------------------------------------------------

-- | Maps to the C @WasmEdge_ErrCategory@ enum.
data ErrCategory
  = -- | Error from the WebAssembly spec (code is 'ErrCode')
    ErrCategory_WASM
  | -- | User-defined error code (e.g., from host functions)
    ErrCategory_UserDefined
  | -- | An unrecognised category (future-proofing)
    ErrCategory_Unknown Word32
  deriving stock (Show, Eq, Generic)
  deriving anyclass (NFData)

-- | Convert a raw C enum value (Word32) to 'ErrCategory'.
mkErrCategory :: Word32 -> ErrCategory
mkErrCategory 0 = ErrCategory_WASM
mkErrCategory 1 = ErrCategory_UserDefined
mkErrCategory n = ErrCategory_Unknown n

-- ---------------------------------------------------------------------------
-- WasmEdgeError
-- ---------------------------------------------------------------------------

{- | An error returned by the WasmEdge runtime.

Thrown as a Haskell exception by all public API functions that encounter
a failed 'WasmEdge_Result'. Can also be caught as 'SomeException'.
-}
data WasmEdgeError = WasmEdgeError
  { weErrCategory :: !ErrCategory
  -- ^ The error category (WASM spec or user-defined).
  , weErrCode :: !Word32
  {- ^ The 24-bit error code.  For WASM errors, this maps to a WasmEdge
  error code enum value.
  -}
  , weErrMessage :: !Text
  -- ^ Human-readable error message from the runtime.
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (Exception, NFData)

-- ---------------------------------------------------------------------------
-- WasmResult
-- ---------------------------------------------------------------------------

{- | A computation that may return a 'WasmEdgeError'.
Use 'throwOnLeft' to re-raise as an exception, or pattern-match directly.
-}
type WasmResult a = Either WasmEdgeError a

-- ---------------------------------------------------------------------------
-- Predicates
-- ---------------------------------------------------------------------------

{- | True if the error has error code 0 (should not happen in practice,
but guards against malformed results).
-}
isSuccess :: WasmEdgeError -> Bool
isSuccess e = weErrCode e == 0

-- | True if this is a user-defined error from a host function.
isUserError :: WasmEdgeError -> Bool
isUserError e = weErrCategory e == ErrCategory_UserDefined

-- | Format a 'WasmEdgeError' into a human-readable string with a hex error code.
formatError :: WasmEdgeError -> String
formatError e =
  "["
    ++ show (weErrCategory e)
    ++ " code: 0x"
    ++ showHex (weErrCode e) ""
    ++ "] "
    ++ show (weErrMessage e)

-- ---------------------------------------------------------------------------
-- Convenience
-- ---------------------------------------------------------------------------

{- | Throw a 'WasmEdgeError' as an IO exception on 'Left', or unwrap 'Right'.

Useful for step-by-step WASM pipelines where you want errors to propagate
as exceptions rather than handling them inline:

@
withVM Nothing Nothing $ \vm -> do
  loadWasmFile vm "module.wasm" >>= throwOnLeft
  validate vm                    >>= throwOnLeft
  instantiate vm                 >>= throwOnLeft
  execute vm "run" []            >>= throwOnLeft
@
-}
throwOnLeft :: WasmResult a -> IO a
throwOnLeft (Left err) = throwIO err
throwOnLeft (Right a) = pure a
