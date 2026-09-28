---
type: File Format
title: DDS texture container
description: On-disk layout of Skyrim SE .dds textures and how OpenSky parses them.
tags: [format, texture, dds, bcn, rgba8888, bgra8888, xrgb8888, rendering]
---

# DDS texture container

Every Skyrim SE texture is a DDS (DirectDraw Surface) file. OpenSky reads 2D textures in
BC1 to BC5 and BC7, and three uncompressed 32-bit layouts: xRGB8888, RGBA8888, and BGRA8888.
Metal has native pixel formats for all of them.

Source: the Microsoft
[DDS programming guide](https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dx-graphics-dds-pguide)
and its pages for `DDS_HEADER`, `DDS_PIXELFORMAT`, `DDS_HEADER_DXT10`, and `dxgiformat.h`.

## File layout

All integers are little-endian.

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | Magic `"DDS "` (`0x20534444`) |
| 4 | 124 | `DDS_HEADER` |
| 128 | 20 | `DDS_HEADER_DXT10`, only when the FourCC is `"DX10"` |
| after | | Mip levels, packed, largest first |

## DDS_HEADER (124 bytes)

| Field | Size | Notes |
| --- | --- | --- |
| dwSize | 4 | Must be 124 |
| dwFlags | 4 | `DDSD_MIPMAPCOUNT` (`0x20000`) makes dwMipMapCount valid |
| dwHeight, dwWidth | 4 + 4 | Height comes first |
| dwPitchOrLinearSize | 4 | Must be `width * 4` for 32-bit layouts |
| dwDepth | 4 | Not used. Volumes are caught by dwCaps2 |
| dwMipMapCount | 4 | Used only with `DDSD_MIPMAPCOUNT`. Otherwise 1 level |
| dwReserved1 | 44 | Skipped |
| ddspf | 32 | `DDS_PIXELFORMAT`, below |
| dwCaps | 4 | Skipped |
| dwCaps2 | 4 | Cubemap `0x200` or volume `0x200000`: not supported |
| dwCaps3, dwCaps4, dwReserved2 | 12 | Skipped |

## DDS_PIXELFORMAT (32 bytes)

| Field | Size | Notes |
| --- | --- | --- |
| dwSize | 4 | Must be 32 |
| dwFlags | 4 | `DDPF_FOURCC` `0x4` for BCn; `DDPF_RGB` `0x40`, alpha `0x1` |
| dwFourCC | 4 | See the list below |
| dwRGBBitCount | 4 | Must be 32 for the uncompressed layouts |
| dwRBitMask, dwGBitMask, dwBBitMask, dwABitMask | 16 | See the table below |

FourCC to format: `DXT1` is BC1, `DXT3` is BC2, `DXT5` is BC3, `ATI1` or `BC4U` is BC4,
`ATI2` or `BC5U` is BC5, and `DX10` means "read `DDS_HEADER_DXT10`". `DXT2` and `DXT4`
(premultiplied alpha) do not appear in SSE and are not supported.

Uncompressed layouts have no FourCC. The masks describe one little-endian 32-bit word:

| Layout | R | G | B | A | Seen in vanilla |
| --- | --- | --- | --- | --- | --- |
| xRGB8888 | `0x00ff0000` | `0x0000ff00` | `0x000000ff` | `0` | Terrain |
| RGBA8888 | `0x000000ff` | `0x0000ff00` | `0x00ff0000` | `0xff000000` | Object LOD atlas |
| BGRA8888 | `0x00ff0000` | `0x0000ff00` | `0x000000ff` | `0xff000000` | Tree LOD atlas |

So xRGB8888 bytes are B, G, R, X. All three need `DDSD_PITCH` and a pitch of `width * 4`.
The X byte of xRGB8888 has no meaning, so OpenSky sets it to 255 before upload. Stored alpha
stays as it is. Other bit counts, flags, or masks are not supported.

## DDS_HEADER_DXT10 (20 bytes)

| Field | Notes |
| --- | --- |
| dxgiFormat | Accepted: BC1 71, BC2 74, BC3 77, BC4 80, BC5 83, BC7 98. The `_SRGB` code is one higher (BC1 72, BC2 75, BC3 78, BC7 99). 81 and 84 are `_SNORM` and not supported |
| resourceDimension | Must be 3 (TEXTURE2D) |
| miscFlag | `0x4` (cube) is not supported |
| arraySize | More than 1 is not supported |
| miscFlags2 | Alpha mode. Skipped |

## Mip level sizes

Levels follow the header with no padding. Level `i` is `max(1, w >> i)` by `max(1, h >> i)`
texels.

- BCn: `ceil(w_i / 4) * ceil(h_i / 4)` blocks of 4x4 texels. A block is 8 bytes for BC1 and
  BC4, and 16 bytes for BC2, BC3, BC5, and BC7.
- 32-bit: `w_i * h_i * 4` bytes. One row is `w_i * 4` bytes.

Example: a 256x128 BC1 texture. Level 0 is 64 x 32 blocks, which is 16384 bytes. Level 1 is
32 x 16 blocks, which is 4096 bytes.

A mip count larger than the full chain (`floor(log2(max(w, h))) + 1`) is an error, and so is
a chain that runs past the end of the file. Extra bytes after the chain are allowed.

## What vanilla uses

A sweep of every `.dds` in the vanilla archives found:

- Only legacy FourCC headers. No DX10 header, so no BC7 and no sRGB flag. Mods use DX10, so
  OpenSky still reads it.
- BC3 is the most common, then BC1, then a few BC2.
- Many uncompressed files: face normal maps (`_msn`), tint masks, interface art, and LOD
  atlases. Some use layouts OpenSky does not read yet. Those, and the cubemaps and one volume
  texture, get placeholder textures.
- Some files have only one mip level. The largest size is 8192, not 4096.

## Color space

The DX10 `_SRGB` flag is only a hint. The renderer picks the color space by how a texture is
used. Diffuse (color) maps use an sRGB Metal format. Normal maps and data maps are linear.
BC4 and BC5 have no sRGB format. Legacy FourCC files carry no color-space information at all.
xRGB8888 and BGRA8888 upload as BGRA8, and RGBA8888 as RGBA8.
