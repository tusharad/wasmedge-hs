// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tushar Adhatrao
// wasmedge-hs: umbrella include for hsc2hs preprocessing
//
// hsc2hs uses this header to resolve #size, #peek, #poke, and #alignment
// macros against the real C struct layouts.

#ifndef WASMEDGE_HS_H
#define WASMEDGE_HS_H

// Bring in the full WasmEdge public API
#include "wasmedge/wasmedge.h"

// Bring in our shim layer
#include "wasmedge_hs_shims.h"

// GHC helper: sizeof wrapper macros are resolved via hsc2hs
// We do not define anything extra here — hsc2hs does the layout queries.

#endif // WASMEDGE_HS_H
