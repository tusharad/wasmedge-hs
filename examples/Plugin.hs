{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import Data.Text qualified as T
import WasmEdge.Plugin

main :: IO ()
main = do
  putStrLn "=== WasmEdge Haskell Binding: Plugin Discovery Example ==="
  putStrLn "Loading plugins from default installation paths..."
  loadPluginsWithDefaultPaths

  plugins <- listPlugins
  putStrLn $ "Found " ++ show (length plugins) ++ " plugin(s)."

  forM_ plugins $ \pName -> do
    putStrLn $ "\nPlugin: " ++ T.unpack pName
    mPlug <- findPlugin pName
    case mPlug of
      Nothing -> putStrLn "  Could not open plugin context"
      Just plug -> do
        name <- getPluginName plug
        putStrLn $ "  Plugin Name: " ++ T.unpack name
        mods <- listPluginModules plug
        putStrLn $ "  Exported Modules: " ++ show (map T.unpack mods)
