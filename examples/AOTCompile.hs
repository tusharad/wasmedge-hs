{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.ByteString qualified as BS
import System.FilePath ((</>))
import System.IO (BufferMode (..), hSetBuffering, stdout)
import System.IO.Temp (withSystemTempDirectory)
import WasmEdge.Compiler
import WasmEdge.Configure
import WasmEdge.Error (formatError)
import WasmEdge.Types (OptimizationLevel (..))

addWasm :: BS.ByteString
addWasm =
  BS.pack
    [ 0x00
    , 0x61
    , 0x73
    , 0x6D
    , 0x01
    , 0x00
    , 0x00
    , 0x00
    , 0x01
    , 0x07
    , 0x01
    , 0x60
    , 0x02
    , 0x7F
    , 0x7F
    , 0x01
    , 0x7F
    , 0x03
    , 0x02
    , 0x01
    , 0x00
    , 0x07
    , 0x07
    , 0x01
    , 0x03
    , 0x61
    , 0x64
    , 0x64
    , 0x00
    , 0x00
    , 0x0A
    , 0x09
    , 0x01
    , 0x07
    , 0x00
    , 0x20
    , 0x00
    , 0x20
    , 0x01
    , 0x6A
    , 0x0B
    ]

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  putStrLn "=== WasmEdge Haskell Binding: AOT Compilation Example ==="
  withSystemTempDirectory "wasmedge_aot_example" $ \tmpDir -> do
    let outSo = tmpDir </> "add_aot.so"
    putStrLn $ "Target output path: " ++ outSo
    withConfigure $ \cfg -> do
      setCompilerOptions cfg (defaultCompilerOptions {compOptLevel = OptO3})
      putStrLn "Configured AOT compiler with OptO3."
      withCompiler (Just cfg) $ \compiler -> do
        putStrLn "Compiling WASM bytecode to native shared object..."
        res <- compileBytes compiler addWasm outSo
        case res of
          Left err -> putStrLn $ "AOT Compilation error: " ++ show (formatError err)
          Right () -> putStrLn $ "AOT Compilation succeeded! Output written to: " ++ outSo
