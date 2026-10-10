// A C interface over the vendored astcenc, so Swift needs no C++ interop.
// See docs/decisions/astcenc.md.

#ifndef CASTCENCODER_H
#define CASTCENCODER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Bytes of ASTC blocks for an image: 16 per block, partial blocks rounded up.
size_t opensky_astc_encoded_size(uint32_t width, uint32_t height, uint32_t block_x,
                                 uint32_t block_y);

/// Encodes straight-alpha RGBA8 rows, top row first, as 2D LDR ASTC blocks.
/// `effort` runs from 0 (fastest) to 100 (exhaustive). Returns 0 on success;
/// otherwise writes astcenc's message into `error`.
int opensky_astc_encode(const uint8_t *rgba, uint32_t width, uint32_t height,
                        uint32_t block_x, uint32_t block_y, float effort, uint8_t *out,
                        size_t out_size, char *error, size_t error_size);

/// Decodes 2D LDR ASTC blocks into RGBA8 rows, top row first. `out` holds
/// `width * height * 4` bytes. Returns 0 on success, as `opensky_astc_encode` does.
int opensky_astc_decode(const uint8_t *blocks, size_t blocks_size, uint32_t width,
                        uint32_t height, uint32_t block_x, uint32_t block_y, uint8_t *out,
                        char *error, size_t error_size);

#ifdef __cplusplus
}
#endif

#endif
