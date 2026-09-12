// SPDX-License-Identifier: Apache-2.0
// wasmedge-hs: uint128_t <-> (uint64_t hi, uint64_t lo) helpers
//
// These are in a separate file because uint128_t is a GCC/Clang extension
// that needs careful handling. Keeping them isolated prevents accidental
// use elsewhere.

#include <stdint.h>
#include <string.h>

// The uint128_t type used by WasmEdge's C API is the built-in GCC/Clang
// __uint128_t. Our shims.c already handles the int128 case inline, but
// these helpers are available for direct use from Haskell if needed.

void hs_uint128_to_words(const uint64_t *v_raw,
                          uint64_t *hi, uint64_t *lo) {
  // v_raw points to 16 bytes representing a uint128_t (little-endian layout)
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
  *lo = v_raw[0];
  *hi = v_raw[1];
#else
  *hi = v_raw[0];
  *lo = v_raw[1];
#endif
}

void hs_uint128_from_words(uint64_t *out_raw,
                            uint64_t hi, uint64_t lo) {
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
  out_raw[0] = lo;
  out_raw[1] = hi;
#else
  out_raw[0] = hi;
  out_raw[1] = lo;
#endif
}
