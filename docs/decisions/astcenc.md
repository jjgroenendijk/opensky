---
type: Decision
title: astcenc for ASTC texture encoding
description: Vendor ARM's astcenc as a static library built from a pinned source tarball, behind a
  small C shim, to encode ASTC textures at every block size and effort level.
tags: [decision, texture, dependency, licensing, astc]
---

# astcenc for ASTC texture encoding

The asset cache may store textures as ASTC, a GPU block format that every Apple Silicon GPU
samples natively. Its block size sets the bits per texel: 4x4 is 8 bits, 12x12 is 0.89 bits.
Comparing and later converting textures needs an ASTC encoder for every block size.

## Decision

- Build [astcenc](https://github.com/ARM-software/astc-encoder) 5.7.0 from its source tarball with
  `tools/vendor-astcenc.sh`, run by `make bootstrap` or alone as `make astcenc`. The script checks
  the tarball's sha256, builds only the core library for NEON with cmake, and installs
  `libastcenc.a`, `astcenc.h`, and the license into `.vendor/astcenc`. That folder is gitignored,
  and linked worktrees share the main checkout's copy, as with ffmpeg.
- Link it statically. The app and `openskycli` carry no extra dylib.
- Wrap it in a C target of the package, `CASTCEncoder`: one C++ file that calls astcenc and a C
  header that Swift imports. Swift needs no C++ interop mode, which would spread to every module
  that imports one that uses it.
- Every astcenc call stays behind `ASTCEncoder` in `OpenSkyRendering`. Callers pass RGBA8 pixels, a
  block size, and an effort preset, and get the encoded blocks or a typed error.

## Why not ImageIO

macOS ImageIO can write ASTC, but only at 4x4 and 8x8. It also ignores
`kCGImageDestinationLossyCompressionQuality` for ASTC: quality 0, 0.5, and 1 give identical bytes
(checked on macOS 26 with a 512x512 noise image). So it offers no block sizes between those two and
no effort setting. Its output also stores the bottom row first, opposite to how Metal reads ASTC.

## Licensing

astcenc is Apache-2.0. Apache-2.0 allows static linking into a program under another license. A
redistributed OpenSky must carry the astcenc license text and its notice; the build keeps
`LICENSE.txt` next to the library for that.

## Build requirement

cmake builds the library; `make bootstrap` installs it with Homebrew. A missing `.vendor/astcenc`
fails the link of any target that imports `OpenSkyRendering`. CI restores the prefix from its cache,
keyed by the vendoring script, and runs `make astcenc` otherwise.
