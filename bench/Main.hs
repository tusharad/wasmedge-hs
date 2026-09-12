-- | Criterion benchmarks for wasmedge-hs
module Main (main) where

import Criterion.Main
import Data.ByteString qualified as BS
import WasmEdge.Types
import WasmEdge.VM

-- Minimal add function WASM (same as in VMSpec)
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

setupVM :: IO VM
setupVM = do
  vm <- createVM Nothing Nothing
  _ <- loadWasmBytes vm addWasm
  _ <- validate vm
  _ <- instantiate vm
  pure vm

main :: IO ()
main =
  defaultMain
    [ bgroup
        "VM lifecycle"
        [ bench "createVM/deleteVM" $ nfIO $ withVM Nothing Nothing $ \_ -> pure ()
        ]
    , bgroup
        "runWasmBytes (one-shot)"
        [ bench "add(1,2)" $
            nfIO $
              withVM Nothing Nothing $ \vm ->
                runWasmBytes vm addWasm "add" [WasmI32 1, WasmI32 2]
        ]
    , bgroup
        "load/validate/instantiate/execute (pipeline)"
        [ bench "add(1,2) pipeline" $
            nfIO $
              withVM Nothing Nothing $ \vm -> do
                _ <- loadWasmBytes vm addWasm
                _ <- validate vm
                _ <- instantiate vm
                execute vm "add" [WasmI32 1, WasmI32 2]
        , envWithCleanup setupVM deleteVM $ \vm ->
            bench "execute only (pre-loaded)" $
              nfIO (execute vm "add" [WasmI32 1, WasmI32 2])
        ]
    ]
