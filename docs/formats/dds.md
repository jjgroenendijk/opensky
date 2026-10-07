---
type: File Format
title: DDS texture container
description: On-disk layout of Skyrim SE .dds textures and how OpenSky reads them.
tags: [format, texture, dds, bcn, rgba8888, bgra8888, xrgb8888, rgb888, rendering]
---

# DDS texture container

DDS (DirectDraw Surface) is the file format of every Skyrim SE texture. OpenSky reads 2D
textures in BC1 to BC5 and BC7, three 32-bit formats (xRGB8888, RGBA8888, and BGRA8888), and
24-bit RGB. Each 32-bit or compressed format maps to a native Metal pixel format. Metal has
no 24-bit format, so the parser widens each 24-bit texel to 4 bytes.

Reference: the Microsoft
[DDS programming guide](https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dx-graphics-dds-pguide)
and its pages for `DDS_HEADER`, `DDS_PIXELFORMAT`, `DDS_HEADER_DXT10`, and `dxgiformat.h`.

## File layout

All integers are little-endian.

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | Magic `"DDS "` (`0x20534444`) |
| 4 | 124 | `DDS_HEADER` |
| 128 | 20 | `DDS_HEADER_DXT10`, only when the FourCC is `"DX10"` |
| after | rest | Mip levels, largest first, no padding |

### DDS_HEADER (124 bytes)

| Field | Size | Notes |
| --- | --- | --- |
| dwSize | 4 | Must be 124 |
| dwFlags | 4 | `DDSD_MIPMAPCOUNT` (`0x20000`) makes dwMipMapCount valid |
| dwHeight, dwWidth | 4 + 4 | Height comes first |
| dwPitchOrLinearSize | 4 | Checked for uncompressed formats only, see below |
| dwDepth | 4 | Not used. Volumes are found through dwCaps2 |
| dwMipMapCount | 4 | Used only with `DDSD_MIPMAPCOUNT`. Otherwise 1 level |
| dwReserved1 | 44 | Skipped |
| ddspf | 32 | `DDS_PIXELFORMAT`, below |
| dwCaps | 4 | Skipped |
| dwCaps2 | 4 | `0x200` cubemap and `0x200000` volume are not supported |
| dwCaps3, dwCaps4, dwReserved2 | 12 | Skipped |

### DDS_PIXELFORMAT (32 bytes)

| Field | Size | Notes |
| --- | --- | --- |
| dwSize | 4 | Must be 32 |
| dwFlags | 4 | `DDPF_FOURCC` `0x4`, `DDPF_RGB` `0x40`, `DDPF_ALPHAPIXELS` `0x1` |
| dwFourCC | 4 | Table below |
| dwRGBBitCount | 4 | 32 or 24 for the uncompressed formats |
| dwRBitMask, dwGBitMask, dwBBitMask, dwABitMask | 16 | Table below |

FourCC to format: `DXT1` BC1, `DXT3` BC2, `DXT5` BC3, `ATI1` or `BC4U` BC4, `ATI2` or `BC5U`
BC5, `DX10` read the DXT10 header. `DXT2` and `DXT4` (premultiplied alpha) do not appear in
Skyrim SE and are not supported.

The 32-bit formats have no FourCC. They use `DDPF_RGB` and bit masks:

| Format | R mask | G mask | B mask | A mask | Bytes in file | Vanilla use |
| --- | --- | --- | --- | --- | --- | --- |
| xRGB8888 | `0x00ff0000` | `0x0000ff00` | `0x000000ff` | 0 | B, G, R, X | Terrain |
| RGBA8888 | `0x000000ff` | `0x0000ff00` | `0x00ff0000` | `0xff000000` | R, G, B, A | Object LOD atlas |
| BGRA8888 | `0x00ff0000` | `0x0000ff00` | `0x000000ff` | `0xff000000` | B, G, R, A | Tree LOD atlas |

RGBA8888 and BGRA8888 also set `DDPF_ALPHAPIXELS`. Other bit counts, flags, or masks are
rejected. The X byte of xRGB8888 has
no defined value, so OpenSky writes 255 there before upload.

24-bit RGB uses `DDPF_RGB` alone, bit count 24, and alpha mask 0. Each of the R, G, and B
masks names one byte of the 3-byte texel: `0xff`, `0xff00`, or `0xff0000`. The vanilla tint
masks use R `0xff0000`, G `0xff00`, B `0xff`, so the bytes are B, G, R. Rows have no padding.
The parser hands out each level as xRGB8888 bytes (B, G, R, 255).

Uncompressed rows have no padding. The size field must match when its flag is set:
`DDSD_PITCH` (`0x8`) needs `width * bytes per texel`, and `DDSD_LINEARSIZE` (`0x80000`) needs
`width * height * bytes per texel`. The tint masks and four 32-bit lens flare and effect
textures set `DDSD_LINEARSIZE`. A file with neither flag is read; the mip chain size check
still applies.

### DDS_HEADER_DXT10 (20 bytes)

| Field | Notes |
| --- | --- |
| dxgiFormat | See below |
| resourceDimension | Must be 3 (`TEXTURE2D`) |
| miscFlag | `0x4` (`TEXTURECUBE`) is not supported |
| arraySize | More than 1 is not supported |
| miscFlags2 | Alpha mode. Skipped |

Accepted `dxgiFormat` values, UNORM: BC1 71, BC2 74, BC3 77, BC4 80, BC5 83, BC7 98. The
`_SRGB` code is UNORM + 1: BC1 72, BC2 75, BC3 78, BC7 99. Codes 81 and 84 are BC4 and BC5
`_SNORM` and are rejected.

## Mip level sizes

Level `i` is `max(1, w >> i)` by `max(1, h >> i)` pixels.

- BCn: `ceil(w_i / 4) * ceil(h_i / 4)` blocks of 4 x 4 pixels. A block is 8 bytes for BC1
  and BC4, and 16 bytes for BC2, BC3, BC5, and BC7.
- 32-bit formats: `w_i * h_i * 4` bytes, with `w_i * 4` bytes per row.
- 24-bit RGB: `w_i * h_i * 3` bytes in the file, `w_i * 4` bytes per row after widening.

A mip count above the full chain (`floor(log2(max(w, h))) + 1`) is an error. So is a chain
that runs past the end of the file. Extra bytes at the end are allowed.

## Vanilla textures

A sweep of every `.dds` in the vanilla archives (about 33,000 files) found:

- Only legacy FourCC headers. No DX10 header, so no BC7 and no declared sRGB. Mods use DX10
  and BC7, so OpenSky still reads them.
- BCn files: mostly BC3, then BC1, and about 150 BC2.
- About 10,000 uncompressed files: face `_msn` normal maps, tint masks, interface art, and
  LOD atlases. OpenSky reads the three 32-bit formats and 24-bit RGB (188 files).
- 58 cubemaps and 1 volume texture throw `unsupported` and get a placeholder. Every other
  vanilla texture parses (census of 32,918 files, 2026-10-07).
- Some textures are 8192 pixels wide, not only 4096.

## Color space

The DX10 `_SRGB` code is only a hint. The renderer chooses the color space by use. A
diffuse texture uses the sRGB Metal format. A normal or data map uses the linear format.
BC4 and BC5 have no sRGB formats. Legacy FourCC files carry no color space at all.

xRGB8888 and BGRA8888 upload as BGRA8. RGBA8888 uploads as RGBA8. Missing alpha becomes
fully opaque. Stored alpha is kept.

## CPU decode

The chargen face is painted on the CPU, so two kinds of file are also decoded there:

- The face color map, such as `textures\actors\character\male\malehead.dds`, is BC1
  (1024 x 1024 on this install).
- The tint masks under `textures\actors\character\character assets\tintmasks\` use a
  24-bit `DDPF_RGB` layout (flags `0x40`, bit count 24) at 512 x 512. The mask is gray, so
  the red channel is the coverage.

The CPU decoder reads the top level of BC1, BC3, the three 32-bit formats, and 24-bit RGB.
A BC1 block with `color0 <= color1` uses the three-color mode with transparent black. A BC3
color block always uses four colors. The painted result is written back as an RGBA8888
file with a box-filtered mip chain, so the normal texture path uploads it.
