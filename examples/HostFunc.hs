{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.ByteString qualified as BS
import Data.Text qualified as T
import System.IO (BufferMode (..), hSetBuffering, stdout)
import WasmEdge.Error (ErrCategory (..), WasmEdgeError (..), WasmResult, formatError)
import WasmEdge.Function
import WasmEdge.Module
import WasmEdge.Types
import WasmEdge.VM

-- WASM guest module that imports "add_one" from "host_module":
-- (module
--   (import "host_module" "add_one" (func $add_one (param i32) (result i32)))
--   (func (export "call_host") (param i32) (result i32)
--     local.get 0
--     call $add_one))
guestWasm :: BS.ByteString
guestWasm =
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
    , 0x06
    , 0x01
    , 0x60
    , 0x01
    , 0x7F
    , 0x01
    , 0x7F -- type 0: (i32) -> i32
    , 0x02
    , 0x17
    , 0x01 -- import section: 1 import
    , 0x0B
    , 0x68
    , 0x6F
    , 0x73
    , 0x74
    , 0x5F
    , 0x6D
    , 0x6F
    , 0x64
    , 0x75
    , 0x6C
    , 0x65 -- "host_module"
    , 0x07
    , 0x61
    , 0x64
    , 0x64
    , 0x5F
    , 0x6F
    , 0x6E
    , 0x65 -- "add_one"
    , 0x00
    , 0x00 -- kind func, type 0
    , 0x03
    , 0x02
    , 0x01
    , 0x00 -- func 1 has type 0
    , 0x07
    , 0x0D
    , 0x01 -- export section: 1 export
    , 0x09
    , 0x63
    , 0x61
    , 0x6C
    , 0x6C
    , 0x5F
    , 0x68
    , 0x6F
    , 0x73
    , 0x74 -- "call_host"
    , 0x00
    , 0x01 -- kind func, func idx 1
    , 0x0A
    , 0x08
    , 0x01 -- code section: 1 func
    , 0x06
    , 0x00 -- size 6, 0 locals
    , 0x20
    , 0x00 -- local.get 0
    , 0x10
    , 0x00 -- call 0 (the imported func)
    , 0x0B -- end
    ]

-- Haskell implementation of the host function
haskellAddOne :: CallingFrame -> [WasmVal] -> IO (WasmResult [WasmVal])
haskellAddOne _ [WasmI32 n] = do
  putStrLn $ "  [Haskell HostFunc] Received value from WASM: " ++ show n
  let result = n + 1
  putStrLn $ "  [Haskell HostFunc] Returning incremented value: " ++ show result
  pure $ Right [WasmI32 result]
haskellAddOne _ args =
  pure $
    Left $
      WasmEdgeError ErrCategory_UserDefined 2 ("add_one: unexpected arguments: " <> T.pack (show args))

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  putStrLn "=== WasmEdge Haskell Binding: Host Function Example ==="
  putStrLn "Step 1: creating function type"

  -- 1. Create function type and host function
  withFunctionType [I32] [I32] $ \fnType -> do
    putStrLn "Step 2: creating host function"
    withFunction fnType haskellAddOne $ \hostFn -> do
      putStrLn "Step 3: building host module"
      -- 2. Build host module exporting "add_one"
      hostMod <- buildHostModule "host_module" $ \b ->
        builderAddFunction b "add_one" hostFn

      putStrLn "Step 4: creating VM"
      -- 3. Run guest WASM in VM with the host module registered
      withVM Nothing Nothing $ \vm -> do
        putStrLn "Step 5: registering host module"
        regRes <- registerModuleFromImport vm hostMod
        case regRes of
          Left err -> putStrLn $ "Registration failed: " ++ formatError err
          Right () -> do
            putStrLn "Host module registered successfully."
            putStrLn "Executing guest WASM function 'call_host(99)'..."
            res <- runWasmBytes vm guestWasm "call_host" [WasmI32 99]
            case res of
              Left err -> putStrLn $ "Execution failed: " ++ formatError err
              Right [WasmI32 ans] -> putStrLn $ "Final result from WASM: " ++ show ans
              Right vals -> putStrLn $ "Unexpected return: " ++ show vals
