{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{- |
Module      : Test.Unit.LiftMemFuncSpec
Description : Tests for liftMemFunc, withWasmBuffer, and Rust Wasm guests
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT

Tests complex data round-trips through Wasm linear memory:
1. Lifted host functions (liftMemFunc)
2. Guest memory execution with string_processor.wasm (JSON ADT round-trips, CPU-intensive algorithms)
3. Guest memory execution with matrix_compute.wasm (2D arrays, stats, transpose, det, multiplication)
-}
module Test.Unit.LiftMemFuncSpec (spec) where

import Control.Monad (void)
import Data.Aeson (FromJSON (..), ToJSON (..), (.!=), (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Int (Int32)
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
import Test.Hspec

import WasmEdge
import WasmEdge.Caller
import WasmEdge.Function
import WasmEdge.Memory.Alloc
import WasmEdge.Memory.Codec
import WasmEdge.Module
import WasmEdge.VM

-- ---------------------------------------------------------------------------
-- Types for string_processor.wasm
-- ---------------------------------------------------------------------------

data StringReq = StringReq
  { reqText :: Text
  , reqRepeat :: Int
  , reqOperations :: [Text]
  }
  deriving stock (Generic, Show, Eq)

instance ToJSON StringReq where
  toJSON r =
    Aeson.object
      [ "text" .= reqText r
      , "repeat" .= reqRepeat r
      , "operations" .= reqOperations r
      ]

instance FromJSON StringReq where
  parseJSON = Aeson.withObject "StringReq" $ \o ->
    StringReq
      <$> o .: "text"
      <*> o .:? "repeat" .!= 1
      <*> o .:? "operations" .!= []

instance WasmMemory StringReq where
  wasmPoke = jsonWasmPoke
  wasmPeek = jsonWasmPeek

data StepInfo = StepInfo
  { stepOperation :: Text
  , stepInputLen :: Int
  , stepOutputLen :: Int
  }
  deriving stock (Generic, Show, Eq)

instance FromJSON StepInfo where
  parseJSON = Aeson.withObject "StepInfo" $ \o ->
    StepInfo
      <$> o .: "operation"
      <*> o .: "input_len"
      <*> o .: "output_len"

instance ToJSON StepInfo where
  toJSON s =
    Aeson.object
      [ "operation" .= stepOperation s
      , "input_len" .= stepInputLen s
      , "output_len" .= stepOutputLen s
      ]

data StringResp = StringResp
  { respResult :: Text
  , respOriginalLen :: Int
  , respProcessedLen :: Int
  , respSteps :: [StepInfo]
  }
  deriving stock (Generic, Show, Eq)

instance FromJSON StringResp where
  parseJSON = Aeson.withObject "StringResp" $ \o ->
    StringResp
      <$> o .: "result"
      <*> o .: "original_len"
      <*> o .: "processed_len"
      <*> o .: "steps"

instance ToJSON StringResp where
  toJSON r =
    Aeson.object
      [ "result" .= respResult r
      , "original_len" .= respOriginalLen r
      , "processed_len" .= respProcessedLen r
      , "steps" .= respSteps r
      ]

instance WasmMemory StringResp where
  wasmPoke = jsonWasmPoke
  wasmPeek = jsonWasmPeek

-- ---------------------------------------------------------------------------
-- Types for matrix_compute.wasm
-- ---------------------------------------------------------------------------

data StatsResult = StatsResult
  { statRows :: Int
  , statCols :: Int
  , statMin :: Double
  , statMax :: Double
  , statMean :: Double
  , statVariance :: Double
  , statFrobeniusNorm :: Double
  , statTrace :: Double
  }
  deriving stock (Generic, Show, Eq)

instance FromJSON StatsResult where
  parseJSON = Aeson.withObject "StatsResult" $ \o ->
    StatsResult
      <$> o .: "rows"
      <*> o .: "cols"
      <*> o .: "min"
      <*> o .: "max"
      <*> o .: "mean"
      <*> o .: "variance"
      <*> o .: "frobenius_norm"
      <*> o .: "trace"

instance ToJSON StatsResult where
  toJSON s =
    Aeson.object
      [ "rows" .= statRows s
      , "cols" .= statCols s
      , "min" .= statMin s
      , "max" .= statMax s
      , "mean" .= statMean s
      , "variance" .= statVariance s
      , "frobenius_norm" .= statFrobeniusNorm s
      , "trace" .= statTrace s
      ]

instance WasmMemory StatsResult where
  wasmPoke = jsonWasmPoke
  wasmPeek = jsonWasmPeek

data DetResult = DetResult
  { detDeterminant :: Double
  , detSize :: Int
  , detPivots :: [Double]
  }
  deriving stock (Generic, Show, Eq)

instance FromJSON DetResult where
  parseJSON = Aeson.withObject "DetResult" $ \o ->
    DetResult
      <$> o .: "determinant"
      <*> o .: "size"
      <*> o .: "pivots"

instance ToJSON DetResult where
  toJSON d =
    Aeson.object
      [ "determinant" .= detDeterminant d
      , "size" .= detSize d
      , "pivots" .= detPivots d
      ]

instance WasmMemory DetResult where
  wasmPoke = jsonWasmPoke
  wasmPeek = jsonWasmPeek

data MatrixResult = MatrixResult
  { resMatrix :: [[Double]]
  , resRows :: Int
  , resCols :: Int
  , resComputationSteps :: Int
  }
  deriving stock (Generic, Show, Eq)

instance FromJSON MatrixResult where
  parseJSON = Aeson.withObject "MatrixResult" $ \o ->
    MatrixResult
      <$> o .: "matrix"
      <*> o .: "rows"
      <*> o .: "cols"
      <*> o .: "computation_steps"

instance ToJSON MatrixResult where
  toJSON (MatrixResult m r c s) =
    Aeson.object
      [ "matrix" .= m
      , "rows" .= r
      , "cols" .= c
      , "computation_steps" .= s
      ]

instance WasmMemory MatrixResult where
  wasmPoke = jsonWasmPoke
  wasmPeek = jsonWasmPeek

newtype MatrixPayload = MatrixPayload [[Double]]
  deriving stock (Generic, Show, Eq)
  deriving newtype (ToJSON, FromJSON)
  deriving (WasmMemory) via (WasmJSON MatrixPayload)

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "LiftMemFunc and Wasm Guest Integration" $ do
  describe "LiftMemFunc host function creation" $ do
    it "creates lifted host function signature" $ do
      let echoFunc (txt :: Text) = pure (Right ("Echo: " <> txt))
          rawHostFn = liftMemFunc echoFunc
      withFunctionType [I32, I32] [I64] $ \ft ->
        withFunction ft rawHostFn $ \_ -> pure ()

    it "creates lifted side-effect host function signature" $ do
      let logFunc (_txt :: Text) = pure (Right ())
          rawHostFn = liftMemFunc_ logFunc
      withFunctionType [I32, I32] [] $ \ft ->
        withFunction ft rawHostFn $ \_ -> pure ()

  describe "string_processor.wasm integration" $ do
    let wasmPath = "test/data/string_processor.wasm"

    it "loads module and executes reverse and caesar operations" $ do
      withVM Nothing Nothing $ \vm -> do
        regRes <- registerModuleFromFile vm "str_proc" wasmPath
        regRes `shouldBe` Right ()

        let req =
              StringReq
                { reqText = "HelloWorld"
                , reqRepeat = 1
                , reqOperations = ["reverse", "caesar"]
                }
        respRes <- withWasmBuffer vm "str_proc" "process_json" defaultConvention req
        case respRes of
          Left err -> expectationFailure $ "Expected success, got: " ++ show err
          Right (resp :: StringResp) -> do
            -- "HelloWorld" reversed -> "dlroWolleH"
            -- ROT13 applied to "dlroWolleH":
            -- d -> q, l -> y, r -> e, o -> b, W -> J, o -> b, l -> y, l -> y, e -> r, H -> U
            respResult resp `shouldBe` "qyebJbyyrU"
            respOriginalLen resp `shouldBe` 10
            length (respSteps resp) `shouldBe` 2

    it "executes run-length encoding (RLE) and edit distance" $ do
      withVM Nothing Nothing $ \vm -> do
        regRes <- registerModuleFromFile vm "str_proc" wasmPath
        regRes `shouldBe` Right ()

        let req =
              StringReq
                { reqText = "AAABBBCCCCDD"
                , reqRepeat = 1
                , reqOperations = ["rle"]
                }
        respRes <- withWasmBuffer vm "str_proc" "process_json" defaultConvention req
        case respRes of
          Left err -> expectationFailure $ "Expected success, got: " ++ show err
          Right (resp :: StringResp) -> do
            respResult resp `shouldBe` "3A3B4C2D"

    it "handles repetition and CPU-intensive edit distance calculation" $ do
      withVM Nothing Nothing $ \vm -> do
        regRes <- registerModuleFromFile vm "str_proc" wasmPath
        regRes `shouldBe` Right ()

        let req =
              StringReq
                { reqText = "wasmedge"
                , reqRepeat = 3
                , reqOperations = ["edit_distance"]
                }
        respRes <- withWasmBuffer vm "str_proc" "process_json" defaultConvention req
        case respRes of
          Left err -> expectationFailure $ "Expected success, got: " ++ show err
          Right (resp :: StringResp) -> do
            respProcessedLen resp `shouldSatisfy` (> 0)
            T.isPrefixOf "edit_dist=" (respResult resp) `shouldBe` True

  describe "matrix_compute.wasm integration" $ do
    let wasmPath = "test/data/matrix_compute.wasm"

    it "computes statistics of a 3x3 matrix" $ do
      withVM Nothing Nothing $ \vm -> do
        regRes <- registerModuleFromFile vm "matrix_mod" wasmPath
        regRes `shouldBe` Right ()

        -- Matrix:
        -- [[1, 2, 3],
        --  [4, 5, 6],
        --  [7, 8, 9]]
        let inputMat = MatrixPayload [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0], [7.0, 8.0, 9.0]]
        res <- withWasmBuffer vm "matrix_mod" "matrix_stats" defaultConvention inputMat
        case res of
          Left err -> expectationFailure $ "Expected stats success, got: " ++ show err
          Right (st :: StatsResult) -> do
            statRows st `shouldBe` 3
            statCols st `shouldBe` 3
            statMin st `shouldBe` 1.0
            statMax st `shouldBe` 9.0
            statMean st `shouldBe` 5.0
            statTrace st `shouldBe` (1.0 + 5.0 + 9.0)

    it "transposes a 2x3 matrix into a 3x2 matrix" $ do
      withVM Nothing Nothing $ \vm -> do
        regRes <- registerModuleFromFile vm "matrix_mod" wasmPath
        regRes `shouldBe` Right ()

        let inputMat = MatrixPayload [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]
        res <- withWasmBuffer vm "matrix_mod" "matrix_transpose" defaultConvention inputMat
        case res of
          Left err -> expectationFailure $ "Expected transpose success, got: " ++ show err
          Right (mr :: MatrixResult) -> do
            resMatrix mr `shouldBe` [[1.0, 4.0], [2.0, 5.0], [3.0, 6.0]]
            resRows mr `shouldBe` 3
            resCols mr `shouldBe` 2

    it "computes determinant of a 3x3 invertible matrix" $ do
      withVM Nothing Nothing $ \vm -> do
        regRes <- registerModuleFromFile vm "matrix_mod" wasmPath
        regRes `shouldBe` Right ()

        -- Matrix:
        -- [[6, 1, 1],
        --  [4, -2, 5],
        --  [2, 8, 7]]
        -- det = 6*(-14-40) - 1*(28-10) + 1*(32 - (-4)) = 6*(-54) - 18 + 36 = -324 - 18 + 36 = -306
        let inputMat = MatrixPayload [[6.0, 1.0, 1.0], [4.0, -2.0, 5.0], [2.0, 8.0, 7.0]]
        res <- withWasmBuffer vm "matrix_mod" "matrix_determinant" defaultConvention inputMat
        case res of
          Left err -> expectationFailure $ "Expected det success, got: " ++ show err
          Right (det :: DetResult) -> do
            detSize det `shouldBe` 3
            abs (detDeterminant det - (-306.0)) `shouldSatisfy` (< 1e-4)

    it "multiplies two matrices via withWasmBuffer2" $ do
      withVM Nothing Nothing $ \vm -> do
        regRes <- registerModuleFromFile vm "matrix_mod" wasmPath
        regRes `shouldBe` Right ()

        -- A = [[1, 2], [3, 4]]
        -- B = [[5, 6], [7, 8]]
        -- A * B = [[19, 22], [43, 50]]
        let matA = MatrixPayload [[1.0, 2.0], [3.0, 4.0]]
            matB = MatrixPayload [[5.0, 6.0], [7.0, 8.0]]
        res <- withWasmBuffer2 vm "matrix_mod" "matrix_multiply" defaultConvention matA matB
        case res of
          Left err -> expectationFailure $ "Expected multiply success, got: " ++ show err
          Right (mr :: MatrixResult) -> do
            resMatrix mr `shouldBe` [[19.0, 22.0], [43.0, 50.0]]
            resRows mr `shouldBe` 2
            resCols mr `shouldBe` 2
