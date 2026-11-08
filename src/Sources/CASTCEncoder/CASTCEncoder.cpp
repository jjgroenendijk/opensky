// The C shim over astcenc's C++ header: one context per call, one thread.

#include "CASTCEncoder.h"

#include <astcenc.h>
#include <cstdio>

namespace {
void report(char *error, size_t error_size, const char *step, astcenc_error status) {
    if (error != nullptr && error_size > 0) {
        std::snprintf(error, error_size, "%s: %s", step, astcenc_get_error_string(status));
    }
}
} // namespace

size_t opensky_astc_encoded_size(uint32_t width, uint32_t height, uint32_t block_x,
                                 uint32_t block_y) {
    size_t wide = (width + block_x - 1) / block_x;
    size_t tall = (height + block_y - 1) / block_y;
    return wide * tall * 16;
}

int opensky_astc_encode(const uint8_t *rgba, uint32_t width, uint32_t height,
                        uint32_t block_x, uint32_t block_y, float effort, uint8_t *out,
                        size_t out_size, char *error, size_t error_size) {
    astcenc_config config;
    astcenc_error status =
        astcenc_config_init(ASTCENC_PRF_LDR, block_x, block_y, 1, effort, 0, &config);
    if (status != ASTCENC_SUCCESS) {
        report(error, error_size, "config", status);
        return 1;
    }
    astcenc_context *context = nullptr;
    status = astcenc_context_alloc(&config, 1, &context, nullptr);
    if (status != ASTCENC_SUCCESS) {
        report(error, error_size, "context", status);
        return 1;
    }
    // astcenc reads but never writes the input slice.
    void *slices[] = {const_cast<uint8_t *>(rgba)};
    astcenc_image image{width, height, 1, ASTCENC_TYPE_U8, slices};
    const astcenc_swizzle swizzle{ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_A};
    status = astcenc_compress_image(context, &image, &swizzle, out, out_size, 0);
    astcenc_context_free(context);
    if (status != ASTCENC_SUCCESS) {
        report(error, error_size, "compress", status);
        return 1;
    }
    return 0;
}

int opensky_astc_decode(const uint8_t *blocks, size_t blocks_size, uint32_t width,
                        uint32_t height, uint32_t block_x, uint32_t block_y, uint8_t *out,
                        char *error, size_t error_size) {
    astcenc_config config;
    astcenc_error status = astcenc_config_init(ASTCENC_PRF_LDR, block_x, block_y, 1,
                                               ASTCENC_PRE_FASTEST, ASTCENC_FLG_DECOMPRESS_ONLY,
                                               &config);
    if (status != ASTCENC_SUCCESS) {
        report(error, error_size, "config", status);
        return 1;
    }
    astcenc_context *context = nullptr;
    status = astcenc_context_alloc(&config, 1, &context, nullptr);
    if (status != ASTCENC_SUCCESS) {
        report(error, error_size, "context", status);
        return 1;
    }
    void *slices[] = {out};
    astcenc_image image{width, height, 1, ASTCENC_TYPE_U8, slices};
    const astcenc_swizzle swizzle{ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_A};
    status = astcenc_decompress_image(context, blocks, blocks_size, &image, &swizzle, 0);
    astcenc_context_free(context);
    if (status != ASTCENC_SUCCESS) {
        report(error, error_size, "decompress", status);
        return 1;
    }
    return 0;
}
