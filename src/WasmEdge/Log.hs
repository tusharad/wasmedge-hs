-- |
-- Module      : WasmEdge.Log
-- Description : WasmEdge runtime logging configuration
-- Copyright   : (c) wasmedge-hs contributors, 2026
-- License     : Apache-2.0
-- Stability   : stable
--
-- Configure the WasmEdge logging system. The logging system is a global
-- singleton — configuration affects all WasmEdge operations in the process.
--
-- Example:
--
-- @
-- import WasmEdge.Log
--
-- main :: IO ()
-- main = do
--   setLogLevel Error
--   -- ... run WasmEdge operations ...
--   logOff  -- silence all output
-- @
module WasmEdge.Log
  ( -- * Log levels
    LogLevel (..)
    -- * Level control
  , setLogLevel
  , setLogError
  , setLogDebug
  , logOff
    -- * Custom callback
  , LogMessage (..)
  , setLogCallback
  , clearLogCallback
  ) where

import Control.Exception    (bracket_)
import Data.IORef
import Data.Text            (Text)
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString    as BS
import Data.Word            (Word32, Word64)
import Foreign.C            (CString, peekCStringLen)
import Foreign.Ptr
import Foreign.Storable
import System.IO.Unsafe     (unsafePerformIO)

import WasmEdge.Internal.FFI.Basic

-- ---------------------------------------------------------------------------
-- LogLevel
-- ---------------------------------------------------------------------------

-- | The WasmEdge log verbosity level.
data LogLevel
  = LogTrace     -- ^ Trace-level (most verbose)
  | LogDebug     -- ^ Debug-level
  | LogInfo      -- ^ Informational
  | LogWarn      -- ^ Warnings only
  | LogError     -- ^ Errors only
  | LogCritical  -- ^ Critical errors only
  deriving stock (Show, Eq, Ord, Bounded, Enum)

logLevelToC :: LogLevel -> Word32
logLevelToC = \case
  LogTrace    -> 0
  LogDebug    -> 1
  LogInfo     -> 2
  LogWarn     -> 3
  LogError    -> 4
  LogCritical -> 5

-- ---------------------------------------------------------------------------
-- Level control
-- ---------------------------------------------------------------------------

-- | Set the global log level.
setLogLevel :: LogLevel -> IO ()
setLogLevel = c_LogSetLevel . logLevelToC

-- | Shortcut: set log level to 'LogError'.
setLogError :: IO ()
setLogError = c_LogSetErrorLevel

-- | Shortcut: set log level to 'LogDebug'.
setLogDebug :: IO ()
setLogDebug = c_LogSetDebugLevel

-- | Disable all logging output.
logOff :: IO ()
logOff = c_LogOff

-- ---------------------------------------------------------------------------
-- Custom callback
-- ---------------------------------------------------------------------------

-- | A structured log message delivered to a custom log callback.
data LogMessage = LogMessage
  { logMsgText    :: !Text
    -- ^ The log message text.
  , logMsgLogger  :: !Text
    -- ^ The name of the logger that produced this message.
  , logMsgLevel   :: !LogLevel
    -- ^ The severity level.
  }
  deriving stock (Show, Eq)

-- Global IORef holds the current FunPtr so we can free it when replaced.
currentCallbackRef :: IORef (Maybe (FunPtr RawLogCallbackT))
currentCallbackRef = unsafePerformIO (newIORef Nothing)
{-# NOINLINE currentCallbackRef #-}

-- | Set a custom log callback. The callback replaces any previously set one.
-- The old callback's 'FunPtr' is freed automatically.
--
-- The raw C struct layout of 'WasmEdge_LogMessage' is:
--
-- @
-- typedef struct WasmEdge_LogMessage {
--   WasmEdge_String Message;    // offset 0
--   WasmEdge_String LoggerName; // offset 16
--   WasmEdge_LogLevel Level;    // offset 32
--   time_t Time;                // offset 36 (platform-dependent)
--   uint64_t ThreadId;          // ...
-- } WasmEdge_LogMessage;
-- @
--
-- We parse the relevant fields via fixed offsets.
setLogCallback :: (LogMessage -> IO ()) -> IO ()
setLogCallback userCb = do
  -- Wrap the Haskell callback
  rawCb <- mkLogCallback $ \msgPtr -> do
    -- Parse WasmEdge_LogMessage
    -- Message.Length at offset 0, Message.Buf at offset 8
    msgLen  <- peekByteOff @Word32 (castPtr msgPtr) 0
    msgBuf  <- peekByteOff @CString (castPtr msgPtr) 8
    logLen  <- peekByteOff @Word32 (castPtr msgPtr) 16
    logBuf  <- peekByteOff @CString (castPtr msgPtr) 24
    lvlW    <- peekByteOff @Word32 (castPtr msgPtr) 32
    msgTxt  <- if msgBuf == nullPtr || msgLen == 0
                 then pure mempty
                 else TE.decodeUtf8Lenient <$> BS.packCStringLen (msgBuf, fromIntegral msgLen)
    logTxt  <- if logBuf == nullPtr || logLen == 0
                 then pure mempty
                 else TE.decodeUtf8Lenient <$> BS.packCStringLen (logBuf, fromIntegral logLen)
    let lvl = toEnum (min (fromIntegral lvlW) (fromEnum LogCritical))
    userCb LogMessage
      { logMsgText   = msgTxt
      , logMsgLogger = logTxt
      , logMsgLevel  = lvl
      }
  -- Free the old callback if any
  old <- readIORef currentCallbackRef
  case old of
    Just fp -> freeHaskellFunPtr fp
    Nothing -> pure ()
  writeIORef currentCallbackRef (Just rawCb)
  c_LogSetCallback rawCb

-- | Remove the custom log callback and restore default logging.
clearLogCallback :: IO ()
clearLogCallback = do
  c_LogSetCallback nullFunPtr
  old <- readIORef currentCallbackRef
  case old of
    Just fp -> freeHaskellFunPtr fp >> writeIORef currentCallbackRef Nothing
    Nothing -> pure ()
