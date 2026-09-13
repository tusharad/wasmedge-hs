{- |
Module      : WasmEdge.Statistics
Description : WasmEdge statistics context
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : stable
-}
module WasmEdge.Statistics
  ( Statistics
  , createStatistics
  , deleteStatistics
  , withStatistics
  , getInstrCount
  , getInstrPerSecond
  , getTotalCost
  , setStatCostTable
  , setStatCostLimit
  , clearStatistics

    -- * Internal / borrowed pointers
  , unsafeStatisticsPtr
  , borrowStatistics
  ) where

import Control.Exception (bracket, throwIO)
import Data.Word (Word64)
import Foreign.C (CDouble (..))
import Foreign.Marshal.Array (withArray)
import Foreign.Ptr

import WasmEdge.Error
import WasmEdge.Internal.FFI.Configure
import WasmEdge.Internal.Ownership
import WasmEdge.Internal.Types

newtype Statistics = Statistics (OwnedCtx StatisticsTag)

createStatistics :: IO Statistics
createStatistics = do
  p <- c_StatisticsCreate
  if p == nullPtr
    then throwIO $ WasmEdgeError ErrCategory_WASM 0 "WasmEdge_StatisticsCreate returned NULL"
    else Statistics <$> mkOwned (appFunPtr c_StatisticsDelete) p

deleteStatistics :: Statistics -> IO ()
deleteStatistics (Statistics o) = finalizeOwned o

withStatistics :: (Statistics -> IO a) -> IO a
withStatistics = bracket createStatistics deleteStatistics

getInstrCount :: Statistics -> IO Word64
getInstrCount (Statistics o) = withOwned o c_StatisticsGetInstrCount

getInstrPerSecond :: Statistics -> IO Double
getInstrPerSecond (Statistics o) = withOwned o $ \p -> do
  CDouble d <- c_StatisticsGetInstrPerSecond p
  pure d

getTotalCost :: Statistics -> IO Word64
getTotalCost (Statistics o) = withOwned o c_StatisticsGetTotalCost

setStatCostTable :: Statistics -> [Word64] -> IO ()
setStatCostTable (Statistics o) costs =
  withOwned o $ \p ->
    withArray costs $ \arr ->
      c_StatisticsSetCostTable p arr (fromIntegral (length costs))

setStatCostLimit :: Statistics -> Word64 -> IO ()
setStatCostLimit (Statistics o) limit = withOwned o $ \p ->
  c_StatisticsSetCostLimit p limit

clearStatistics :: Statistics -> IO ()
clearStatistics (Statistics o) = withOwned o c_StatisticsClear

-- | Extract the raw pointer of a 'Statistics' context.
unsafeStatisticsPtr :: Statistics -> IO (Ptr StatisticsTag)
unsafeStatisticsPtr (Statistics o) = withOwned o pure

-- | Create a borrowed 'Statistics' context from a raw pointer.
borrowStatistics :: Ptr StatisticsTag -> IO Statistics
borrowStatistics p = Statistics <$> mkOwned (\_ -> pure ()) p

appFunPtr :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
appFunPtr = mkDeleter

foreign import ccall "dynamic"
  mkDeleter :: FunPtr (Ptr a -> IO ()) -> Ptr a -> IO ()
