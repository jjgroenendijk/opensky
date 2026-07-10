---
type: File Format
title: DDS texture container
description: On-disk layout of Skyrim SE .dds textures and how OpenSky parses them.
tags: [format, texture, dds, bcn, rendering]
timestamp: 2026-07-10T00:00:00Z
---

# DDS texture container

DirectDraw Surface — every Skyrim SE texture (`textures/**/*.dds` inside the texture
BSAs, plus loose overrides). OpenSky reads the 2D block-compressed subset vanilla ships:
BC1-BC5, BC7. Parser: `opensky/Formats/DDS/DDSFile.swift`. GPU upload: 2.5 renderer
work, `MTLTexture` via BCn pixel formats (native on Apple Silicon).

Reference: Microsoft DDS programming guide + struct pages —
`DDS_HEADER`, `DDS_PIXELFORMAT`, `DDS_HEADER_DXT10`, dxgiformat.h.
<https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dx-graphics-dds-pguide>

## File layout

All little-endian.

| offset | size | field |
| ------ | ---- | ----- |
| 0 | 4 | magic `"DDS "` (0x20534444) |
| 4 | 124 | `DDS_HEADER` |
| 128 | 20 | `DDS_HEADER_DXT10` — only when pixel format FourCC = `"DX10"` |
| after | — | mip chain, tightly packed, largest level first |

### DDS_HEADER (124 bytes, incl. its own dwSize)

| field | size | notes |
| ----- | ---- | ----- |
| dwSize | 4 | must be 124 |
| dwFlags | 4 | `DDSD_MIPMAPCOUNT` 0x20000 gates dwMipMapCount |
| dwHeight, dwWidth | 4+4 | height first |
| dwPitchOrLinearSize | 4 | unreliable in the wild -> ignored, sizes derived |
| dwDepth | 4 | volumes rejected via caps2 instead |
| dwMipMapCount | 4 | honored only with `DDSD_MIPMAPCOUNT`; else 1 level |
| dwReserved1 | 44 | 11 x uint32, skipped |
| ddspf | 32 | `DDS_PIXELFORMAT`, below |
| dwCaps | 4 | skipped |
| dwCaps2 | 4 | `DDSCAPS2_CUBEMAP` 0x200, `DDSCAPS2_VOLUME` 0x200000 -> `unsupported` |
| dwCaps3, dwCaps4, dwReserved2 | 12 | skipped |

### DDS_PIXELFORMAT (32 bytes)

| field | size | notes |
| ----- | ---- | ----- |
| dwSize | 4 | must be 32 |
| dwFlags | 4 | `DDPF_FOURCC` 0x4 required — uncompressed RGB is `unsupported` |
| dwFourCC | 4 | see mapping below |
| dwRGBBitCount + 4 masks | 20 | uncompressed-only, skipped |

FourCC -> format: `DXT1`->BC1, `DXT3`->BC2, `DXT5`->BC3, `ATI1`/`BC4U`->BC4,
`ATI2`/`BC5U`->BC5, `DX10`-> read `DDS_HEADER_DXT10`. (`DXT2`/`DXT4` premultiplied
variants unseen in SSE -> `unsupported`.)

### DDS_HEADER_DXT10 (20 bytes)

| field | notes |
| ----- | ----- |
| dxgiFormat | UNORM codes accepted: BC1 71, BC2 74, BC3 77, BC4 80, BC5 83, BC7 98; `_SRGB` = UNORM+1 (BC1 72, BC2 75, BC3 78, BC7 99) -> `declaresSRGB`. 81/84 are BC4/BC5 `_SNORM`, rejected |
| resourceDimension | must be 3 (TEXTURE2D) |
| miscFlag | 0x4 (TEXTURECUBE) -> `unsupported` |
| arraySize | > 1 -> `unsupported` |
| miscFlags2 | alpha mode, skipped |

## Mip chain math

Levels are tightly packed after the header(s), no padding. Level `i` is
`max(1, w >> i)` x `max(1, h >> i)` texels = `ceil(w_i/4) * ceil(h_i/4)` 4x4 blocks.
Bytes per block: 8 for BC1/BC4, 16 for BC2/BC3/BC5/BC7. `bytesPerRow(level)` =
blocks-wide x block size — the `MTLTexture.replace` stride. Claimed mip count beyond
the full chain (`floor(log2(max(w,h))) + 1`) or a chain running past EOF ->
`malformed`; trailing extra bytes tolerated.

## Observed in vanilla SSE (2.5 probe)

Sweep of every `.dds` in the local install's BSAs (Textures0-8, Interface,
_ResourcePack, CC Fish/AdvDSGS/Curios): 32 920 files.

* BCn, parsed clean: 22 636 — BC3 18 074, BC1 4 417, BC2 145. Zero DX10
  headers -> zero BC7, zero declared-sRGB; vanilla is legacy-FourCC only
  (DX10/BC7 path still needed: standard for mods).
* Unsupported by design: 10 225 uncompressed RGB (DDPF_RGB — face `_msn`
  normal maps, tint masks, interface art), 58 cubemaps, 1 volume. All ->
  typed error -> placeholder. Uncompressed support deferred until character
  rendering needs it; exterior statics are fully BCn.
* 150 single-mip files; max dimension 8192 (not 4096).
* Farmhouse texture set (candidate 2.7 cell area): 64 files, full decode +
  `MTLTexture` upload, zero failures.

## Color space

`declaresSRGB` (DX10 `_SRGB` code) is advisory only. The renderer picks color space
per usage: diffuse -> sRGB `MTLPixelFormat` variant, normal/data maps -> linear
(BC4/BC5 have no sRGB variants). Legacy-FourCC files carry no color-space info at all.
