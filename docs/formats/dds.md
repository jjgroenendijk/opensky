---
type: File Format
title: DDS texture container
description: On-disk layout of Skyrim SE .dds textures and how OpenSky parses them.
tags: [format, texture, dds, bcn, rgba8888, bgra8888, xrgb8888, rendering]
timestamp: 2026-07-21T00:00:00Z
---

# DDS texture container

DirectDraw Surface — every Skyrim SE texture (`textures/**/*.dds` inside the texture
BSAs, plus loose overrides). OpenSky reads 2D BC1-BC5/BC7 plus legacy 32-bit xRGB8888,
RGBA8888, and BGRA8888. Parser: `opensky/Formats/DDS/DDSFile.swift`. GPU upload: `MTLTexture` via
native BCn/BGRA8/RGBA8 pixel formats.

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
| dwPitchOrLinearSize | 4 | xRGB8888 requires `width * 4`; BCn sizes derived |
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
| dwFlags | 4 | `DDPF_FOURCC` 0x4 for BCn; `DDPF_RGB` 0x40, optional alpha 0x1 |
| dwFourCC | 4 | see mapping below |
| dwRGBBitCount | 4 | xRGB8888 must be 32 |
| dwRBitMask | 4 | xRGB8888 `0x00ff0000` |
| dwGBitMask | 4 | xRGB8888 `0x0000ff00` |
| dwBBitMask | 4 | xRGB8888 `0x000000ff` |
| dwABitMask | 4 | xRGB8888 `0x00000000` |

FourCC -> format: `DXT1`->BC1, `DXT3`->BC2, `DXT5`->BC3, `ATI1`/`BC4U`->BC4,
`ATI2`/`BC5U`->BC5, `DX10`-> read `DDS_HEADER_DXT10`. (`DXT2`/`DXT4` premultiplied
variants unseen in SSE -> `unsupported`.)

Legacy xRGB8888 has no FourCC. `DDPF_RGB` + masks above describe a little-endian 32-bit
word, so payload bytes are B,G,R,X. Parser also accepts `DDPF_RGB | DDPF_ALPHAPIXELS`
RGBA8888 (`R=0x000000ff`, `G=0x0000ff00`, `B=0x00ff0000`, `A=0xff000000`) used by
vanilla object LOD atlas. BGRA8888 (`R=0x00ff0000`, `G=0x0000ff00`, `B=0x000000ff`,
`A=0xff000000`) carries stored alpha in vanilla tree LOD atlas. All require `DDSD_PITCH` +
top-level pitch `width * 4`; other bit depths/flags/masks reject. xRGB X is undefined ->
uploader writes 255 before BGRA8 upload; RGBA/BGRA alpha stays unchanged.

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
`max(1, w >> i)` x `max(1, h >> i)` texels. BCn = `ceil(w_i/4) * ceil(h_i/4)` 4x4
blocks: 8 bytes for BC1/BC4, 16 for BC2/BC3/BC5/BC7. 32-bit RGB = `w_i * h_i * 4`,
`bytesPerRow(level) = w_i * 4`. Claimed mip count beyond full chain
(`floor(log2(max(w,h))) + 1`) or chain running past EOF -> `malformed`; trailing extra
bytes tolerated.

## Observed in vanilla SSE (2.5 probe)

Sweep of every `.dds` in the local install's BSAs (Textures0-8, Interface,
_ResourcePack, CC Fish/AdvDSGS/Curios): 32 920 files.

* BCn, parsed clean: 22 636 — BC3 18 074, BC1 4 417, BC2 145. Zero DX10
  headers -> zero BC7, zero declared-sRGB; vanilla is legacy-FourCC only
  (DX10/BC7 path still needed: standard for mods).
* Initial sweep found 10 225 uncompressed RGB files (face `_msn` normal maps, tint masks,
  interface art, LOD diffuse atlases), 58 cubemaps, 1 volume. xRGB8888 terrain, RGBA8888
  object LOD, and BGRA8888 tree LOD diffuse maps now parse; other uncompressed layouts,
  cubemaps + volumes remain typed errors -> placeholders.
* 150 single-mip files; max dimension 8192 (not 4096).
* Farmhouse texture set (candidate 2.7 cell area): 64 files, full decode +
  `MTLTexture` upload, zero failures.

## Color space

`declaresSRGB` (DX10 `_SRGB` code) is advisory only. The renderer picks color space
per usage: diffuse -> sRGB `MTLPixelFormat` variant, normal/data maps -> linear
(BC4/BC5 have no sRGB variants). Legacy-FourCC files carry no color-space info at all.
32-bit RGB follows same usage policy: xRGB8888/BGRA8888 -> BGRA8, RGBA8888 -> RGBA8;
diffuse uses sRGB, data uses linear. Absent xRGB alpha becomes fully opaque; stored alpha
remains.
