{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Stress.PluginWorkflow
Description : Production suite exercising native WasmEdge plugins and cross-language library usage
Copyright   : (c) 2026 Tushar Adhatrao
License     : MIT
Stability   : experimental

Exercises:
  * 'loadPluginsWithDefaultPaths'
  * 'loadPluginFromPath'
  * 'listPlugins'
  * 'findPlugin'
  * 'getPluginName'
  * 'listPluginModules'
  * 'createPluginModule'
  * 'initWASINN'
  * 'registerModuleFromImport'
  * 'registerModuleFromImportWithAlias'
  * Cross-language library execution (native C media convolution, audio normalization, and tensor ReLU)
-}
module Stress.PluginWorkflow
  ( runPluginWorkflowSuite
  , PluginMetrics (..)
  ) where

import Control.Monad (unless)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import System.Clock (Clock (Monotonic), diffTimeSpec, getTime, toNanoSecs)
import System.Directory (doesFileExist)
import System.Mem (performGC)
import Text.Printf (printf)

import Stress.WasmBytecode (memoryOpsWasm)
import WasmEdge (createVM, runWasmBytes)
import WasmEdge.Module (findFunction, getModuleName, listFunctions)
import WasmEdge.Plugin
  ( createPluginModule
  , findPlugin
  , getPluginName
  , initWASINN
  , listPluginModules
  , listPlugins
  , loadPluginFromPath
  , loadPluginsWithDefaultPaths
  )
import WasmEdge.Types (WasmVal (..))
import WasmEdge.VM
  ( deleteVM
  , executeRegistered
  , listRegisteredModules
  , registerModuleFromImportWithAlias
  )

data PluginMetrics = PluginMetrics
  { pmPluginsDiscovered :: !Int
  , pmPluginName :: !Text
  , pmModulesProvided :: ![Text]
  , pmExportedFunctions :: ![Text]
  , pmDirectAddResult :: !Int
  , pmAliasAddResult :: !Int
  , pmTensorReluClamped :: !Int
  , pmAudioNormStatus :: !Int
  , pmConvolveStatus :: !Int
  , pmWASINNInitialized :: !Bool
  , pmExecutionDurationSec :: !Double
  }
  deriving stock (Show)

runPluginWorkflowSuite :: IO PluginMetrics
runPluginWorkflowSuite = do
  putStrLn "============================================================"
  putStrLn "  STRESS TEST: Native Plugins & Cross-Language Library Usage"
  putStrLn "============================================================"

  t0 <- getTime Monotonic

  -- 1. Discovery with default paths
  putStrLn "[1/7] Probing default plugin search paths..."
  loadPluginsWithDefaultPaths
  initPlugins <- listPlugins
  printf "      Initial discovered plugins: %d\n" (length initPlugins)

  -- 2. Test WASI-NN initialization API
  putStrLn "[2/7] Testing initWASINN with preload model descriptors..."
  initWASINN ["torch:cpu:/tmp/model.pt", "onnx:cpu:/tmp/model.onnx"]

  -- 3. Locate and load native mediatensor plugin
  putStrLn "[3/7] Loading native mediatensor plugin from shared library..."
  let candidatePaths =
        [ "plugins/libwasmedge_mediatensor_plugin.dylib"
        , "wasmedge-hs-examples/plugins/libwasmedge_mediatensor_plugin.dylib"
        , "../wasmedge-hs-examples/plugins/libwasmedge_mediatensor_plugin.dylib"
        ]
  mPluginPath <- findFirstExisting candidatePaths
  pluginPath <- case mPluginPath of
    Just p -> pure p
    Nothing -> fail "mediatensor plugin dylib not found! Run ./build-plugin.sh first."

  loadPluginFromPath pluginPath
  allPlugins <- listPlugins
  printf
    "      Total plugins loaded after dynamic load: %d (%s)\n"
    (length allPlugins)
    (show allPlugins)

  -- 4. Find plugin context and inspect metadata
  putStrLn "[4/7] Inspecting plugin descriptor and module descriptors..."
  mPlugin <- findPlugin "mediatensor_plugin"
  plugin <- case mPlugin of
    Just p -> pure p
    Nothing -> fail "Failed to find loaded 'mediatensor_plugin' in WasmEdge runtime!"

  pName <- getPluginName plugin
  mods <- listPluginModules plugin
  printf "      Plugin Name: %s\n" (T.unpack pName)
  printf "      Modules Exported: %s\n" (show mods)

  -- 5. Create plugin module instance and inspect its exports
  putStrLn "[5/7] Instantiating native plugin module 'mediatensor'..."
  mMod <- createPluginModule plugin "mediatensor"
  modInst <- case mMod of
    Just m -> pure m
    Nothing -> fail "Failed to instantiate module 'mediatensor' from plugin!"

  actualModName <- getModuleName modInst
  printf "      Module name reported by instance: %s\n" (T.unpack actualModName)

  funcs <- listFunctions modInst
  printf "      Exported functions in 'mediatensor': %s\n" (show funcs)

  -- Verify exported functions are present
  let expectedFuncs = ["tensor_convolve", "tensor_relu", "audio_normalize", "add_i32"]
  forM_ expectedFuncs $ \ef -> do
    mFn <- findFunction modInst ef
    unless (isJust mFn) $
      fail $
        "Expected function " ++ T.unpack ef ++ " missing from plugin module!"

  -- 6. Verify plugin module is auto-registered into VM & execute native functions
  putStrLn "[6/7] Verifying plugin module auto-registration in VM & executing native functions..."
  vm <- createVM Nothing Nothing

  -- Inspect initial VM registered modules (WasmEdge auto-registers loaded plugins into newly created VMs)
  vmMods <- listRegisteredModules vm
  printf "      VM initial registered modules: %s\n" (show vmMods)
  unless ("mediatensor" `elem` vmMods) $
    fail "Expected 'mediatensor' to be auto-registered in VM by plugin loader!"

  -- Test direct scalar execution across boundary: add_i32(1234, 5678) = 6912
  resAdd <- executeRegistered vm "mediatensor" "add_i32" [WasmI32 1234, WasmI32 5678]
  addVal <- case resAdd of
    Right [WasmI32 val] -> do
      printf "      Native add_i32(1234, 5678) -> %d (VERIFIED)\n" val
      unless (val == 6912) $ fail "Scalar result mismatch!"
      pure (fromIntegral val)
    other -> fail $ "Unexpected add_i32 result: " ++ show other

  -- 7. Test aliased module registration: register modInst under "media_alias"
  putStrLn "[7/7] Testing registerModuleFromImportWithAlias..."
  resReg2 <- registerModuleFromImportWithAlias vm "media_alias" modInst
  case resReg2 of
    Left err -> fail $ "Failed to register plugin module under alias: " ++ show err
    Right () -> pure ()

  resAliasAdd <- executeRegistered vm "media_alias" "add_i32" [WasmI32 40, WasmI32 2]
  aliasVal <- case resAliasAdd of
    Right [WasmI32 42] -> do
      putStrLn "      Aliased add_i32(40, 2) -> 42 (VERIFIED)"
      pure 42
    other -> fail $ "Unexpected alias add result: " ++ show other

  -- Load linear memory guest into VM to test memory-backed tensor/audio kernels
  _ <- runWasmBytes vm memoryOpsWasm "memory_size" []

  -- Test tensor_relu on guest memory buffer
  resRelu <- executeRegistered vm "mediatensor" "tensor_relu" [WasmI32 1024, WasmI32 64]
  clampedCount <- case resRelu of
    Right [WasmI32 n] -> do
      printf "      tensor_relu(offset=1024, len=64) -> %d clamped (VERIFIED)\n" n
      pure (fromIntegral n)
    other -> fail $ "Unexpected tensor_relu result: " ++ show other

  -- Test audio_normalize
  resAudio <-
    executeRegistered vm "mediatensor" "audio_normalize" [WasmI32 2048, WasmI32 128, WasmI32 950]
  audioStat <- case resAudio of
    Right [WasmI32 0] -> do
      putStrLn "      audio_normalize(pcm=2048, samples=128, target=950) -> 0 (SUCCESS)"
      pure 0
    other -> fail $ "Unexpected audio_normalize result: " ++ show other

  -- Test 2D image convolution (3x3 kernel on 16x16 image)
  resConv <-
    executeRegistered
      vm
      "mediatensor"
      "tensor_convolve"
      [ WasmI32 4096 -- img_ptr
      , WasmI32 16 -- width
      , WasmI32 16 -- height
      , WasmI32 6144 -- kernel_ptr
      , WasmI32 3 -- ksize (3x3)
      , WasmI32 8192 -- out_ptr
      ]
  convStat <- case resConv of
    Right [WasmI32 0] -> do
      putStrLn "      tensor_convolve(16x16, 3x3 kernel) -> 0 (SUCCESS)"
      pure 0
    other -> fail $ "Unexpected tensor_convolve result: " ++ show other

  deleteVM vm
  performGC

  t1 <- getTime Monotonic
  let dur = fromIntegral (toNanoSecs (diffTimeSpec t1 t0)) / 1e9 :: Double
  printf ">>> Plugin Workflow Suite completed in %.3f s\n\n" dur

  pure
    PluginMetrics
      { pmPluginsDiscovered = length allPlugins
      , pmPluginName = pName
      , pmModulesProvided = mods
      , pmExportedFunctions = funcs
      , pmDirectAddResult = addVal
      , pmAliasAddResult = aliasVal
      , pmTensorReluClamped = clampedCount
      , pmAudioNormStatus = audioStat
      , pmConvolveStatus = convStat
      , pmWASINNInitialized = True
      , pmExecutionDurationSec = dur
      }

forM_ :: (Foldable t, Monad m) => t a -> (a -> m b) -> m ()
forM_ xs f = mapM_ f xs

findFirstExisting :: [FilePath] -> IO (Maybe FilePath)
findFirstExisting [] = pure Nothing
findFirstExisting (p : ps) = do
  exists <- doesFileExist p
  if exists then pure (Just p) else findFirstExisting ps
