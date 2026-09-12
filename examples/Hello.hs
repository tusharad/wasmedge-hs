{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.ByteString qualified as BS
import WasmEdge.Error (formatError)
import WasmEdge.Types
import WasmEdge.VM

-- Minimal add function WebAssembly module bytecode:
-- (module
--   (func (export "add") (param i32 i32) (result i32)
--     local.get 0
--     local.get 1
--     i32.add))
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
    , 0x00 -- magic & version 1
    , 0x01
    , 0x07
    , 0x01
    , 0x60
    , 0x02
    , 0x7F
    , 0x7F
    , 0x01
    , 0x7F -- type: (i32, i32) -> i32
    , 0x03
    , 0x02
    , 0x01
    , 0x00 -- function 0 has type 0
    , 0x07
    , 0x07
    , 0x01
    , 0x03
    , 0x61
    , 0x64
    , 0x64
    , 0x00
    , 0x00 -- export "add"
    , 0x0A
    , 0x09
    , 0x01
    , 0x07
    , 0x00 -- code body
    , 0x20
    , 0x00 -- local.get 0
    , 0x20
    , 0x01 -- local.get 1
    , 0x6A -- i32.add
    , 0x0B -- end
    ]

main :: IO ()
main = do
  putStrLn "=== WasmEdge Haskell Binding: Hello Example ==="
  withVM Nothing Nothing $ \vm -> do
    putStrLn "Executing 'add(40, 2)' via WasmEdge VM..."
    result <- runWasmBytes vm addWasm "add" [WasmI32 40, WasmI32 2]
    case result of
      Left err -> putStrLn $ "Execution failed: " ++ show (formatError err)
      Right [WasmI32 val] -> putStrLn $ "Result: 40 + 2 = " ++ show val
      Right vals -> putStrLn $ "Unexpected return: " ++ show vals
