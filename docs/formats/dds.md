---
type: File Format
title: DDS texture container
description: On-disk layout of Skyrim SE .dds textures and how OpenSky reads them.
tags: [format, texture, dds, bcn, rgba8888, bgra8888, xrgb8888, rgb888, l8, volume, rendering]
---

# DDS texture container

DDS (DirectDraw Surface) is the file format of every Skyrim SE texture. OpenSky reads 2D
textures in BC1 to BC5 and BC7, three 32-bit formats (xRGB8888, RGBA8888, and BGRA8888),
24-bit RGB, and 8-bit luminance (L8). Each 32-bit or compressed format maps to a native Metal
pixel format. Metal has no 24-bit or luminance format, so the parser widens each 24-bit or L8
texel to 4 bytes. It also reads cubemaps and volume (3D) textures when the caller asks.

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
| dwDepth | 4 | Slice count, read only for a volume. Volumes are found through dwCaps2 |
| dwMipMapCount | 4 | Used only with `DDSD_MIPMAPCOUNT`. Otherwise 1 level |
| dwReserved1 | 44 | Skipped |
| ddspf | 32 | `DDS_PIXELFORMAT`, below |
| dwCaps | 4 | Skipped |
| dwCaps2 | 4 | `0x200` cubemap, read only for a cube map use. `0x200000` volume, read only for a volume use |
| dwCaps3, dwCaps4, dwReserved2 | 12 | Skipped |

### DDS_PIXELFORMAT (32 bytes)

| Field | Size | Notes |
| --- | --- | --- |
| dwSize | 4 | Must be 32 |
| dwFlags | 4 | `DDPF_FOURCC` `0x4`, `DDPF_RGB` `0x40`, `DDPF_ALPHAPIXELS` `0x1`, `DDPF_LUMINANCE` `0x20000` |
| dwFourCC | 4 | Table below |
| dwRGBBitCount | 4 | 32 or 24 for the uncompressed RGB formats, 8 for L8 |
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

8-bit luminance uses `DDPF_LUMINANCE` alone, bit count 8, and R mask `0xff`. Each byte is
one grey texel. Direct3D samples L8 as (L, L, L, 1), so the parser hands out each level as
xRGB8888 bytes (L, L, L, 255). Luminance with alpha (`DDPF_ALPHAPIXELS`) or a wider bit count
is rejected; no vanilla file uses it. Source: Microsoft `DDS_PIXELFORMAT` and "Map Direct3D 9
formats to Direct3D 10" (`D3DFMT_L8`).

Uncompressed rows have no padding. The size field must match when its flag is set:
`DDSD_PITCH` (`0x8`) needs `width * bytes per texel`, and `DDSD_LINEARSIZE` (`0x80000`) needs
`width * height * bytes per texel`. The tint masks and four 32-bit lens flare and effect
textures set `DDSD_LINEARSIZE`. A file with neither flag is read; the mip chain size check
still applies.

### DDS_HEADER_DXT10 (20 bytes)

| Field | Notes |
| --- | --- |
| dxgiFormat | See below |
| resourceDimension | 3 (`TEXTURE2D`), or 4 (`TEXTURE3D`) for a volume. Others are not supported |
| miscFlag | `0x4` (`TEXTURECUBE`) marks a cubemap, read only for a cube map use |
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

A volume level `i` has `max(1, d >> i)` slices, where `d` is dwDepth. The level stores its
slices one after another, front to back, so its size is the slice size times the slice count.
Source: Microsoft, "DDS file layout for textures" (volume textures).

A mip count above the full chain (`floor(log2(max(w, h, d))) + 1`) is an error. So is a chain
that runs past the end of the file. Extra bytes at the end are allowed.

## Vanilla textures

A sweep of every `.dds` in the vanilla archives (about 33,000 files) found:

- Only legacy FourCC headers. No DX10 header, so no BC7 and no declared sRGB. Mods use DX10
  and BC7, so OpenSky still reads them.
- BCn files: mostly BC3, then BC1, and about 150 BC2.
- About 10,000 uncompressed files: face `_msn` normal maps, tint masks, interface art, and
  LOD atlases. OpenSky reads the three 32-bit formats and 24-bit RGB (188 files).
- 58 cubemaps, such as `textures\cubemaps\EyeCubeMap.dds`. A cubemap used as a 2D texture
  throws `unsupported` and gets a placeholder.
- 1 volume texture, `textures\effects\noisevolume.dds`: L8, 128 x 128 x 128, 8 mip levels, no DX10
  header, and `DDSD_DEPTH` (`0x800000`) set in dwFlags. The file is 2,396,873 bytes: the 128-byte
  header plus the sum of `n * n * n` for n = 128, 64, ..., 1. This exact match confirms the
  slices-per-level layout. Its only use is described in [Volume textures](#volume-textures).
- Every vanilla texture parses (census of 32,918 files).

## Cubemaps

A cubemap stores six square faces one after another, each with its own full mip chain, in
the order +X, -X, +Y, -Y, +Z, -Z. A legacy header sets `DDSCAPS2_CUBEMAP` (`0x200`) and one
bit per face (`0xFC00`). OpenSky needs all six faces. A DX10 header sets `miscFlag` `0x4`
instead. Source: Microsoft, "DDS file layout for textures" and `DDS_HEADER`.

The parser reads a cubemap only when the caller asks for a cube map, because a 2D slot
cannot sample one. The renderer loads environment maps that way and uploads them as a
Metal cube texture. A missing or broken cube map gets a black cube, so it reflects
nothing.

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
It can also read one small mip instead: the terrain LOD brightness fit needs only the mean
colour of a texture, and a 4 x 4 mip of a Skyrim texture has the same mean as its top level
to within 5 percent.
A BC1 block with `color0 <= color1` uses the three-color mode with transparent black. A BC3
color block always uses four colors. The painted result is written back as an RGBA8888
file with a box-filtered mip chain, so the normal texture path uploads it.

## Volume textures

### Where the game uses the noise volume

A byte search of every vanilla archive (meshes decompressed), every plugin, and
`SkyrimSE.exe` for `noisevolume` found one consumer. On 2026-10-31:

- Two Dragonborn meshes, `meshes\dlc02\effects\mq03skaalvilliagebarrier02.nif` and
  `...03.nif`, name `textures\effects\NoiseVolume.dds` as the `BSEffectShaderProperty`
  source texture of one shape, `CloudsReversed01:0` (clamp mode 3, wrap). The shape is one
  layer of the storm barrier around the Skaal village.
- No vanilla record places either mesh. The one placed barrier, the `STAT`
  `MQ03SkaalVillageBarrier01` (`Dragonborn.esm:029D26`), uses
  `mq03skaalvilliagebarrier.nif`, which does not use the volume.
- No other mesh, plugin record, or the game program names the file.

So the real game never shows the noise volume, and the reference game cannot show how a
volume in a 2D effect slot looks. Direct3D 11 does not define the result of sampling a 3D
resource through a 2D shader slot.

### How OpenSky draws it

- The loader uploads a volume as a Metal 3D texture with its full mip chain, one slice
  after another per level. A volume that fails to load gets a mid-grey 1 x 1 x 1 volume, so
  the frame goes on.
- A colour load of a volume file gets the 2D colour placeholder, because a 2D slot cannot
  sample it. The texture library remembers that the file is a volume.
- An effect shape on a static mesh asks for its source as an effect source. For a volume
  file it gets the 3D texture, which binds to its own shader slot, and the shader samples it
  at the shape's UV and depth 0.5, the middle slice.
  [UNCONFIRMED] The depth 0.5 is OpenSky's choice. The game may sample another depth, show
  nothing, or show something else. Particles and every other 2D consumer keep the
  placeholder.

The noise does not change OpenSky's frame of the barrier mesh. The shape's flags turn on
vertex colours and vertex alpha. Its vertex colours are black over almost all of the shape,
and its base colour is (0.196, 0.196, 0.216), so its effect colour is near zero whatever
the source holds. An L8 texel has alpha 1, the same as the placeholder. So the shape is a
dark, semi-transparent layer, and a capture with the volume matches one with the placeholder
byte for byte. A temporary shader edit that coloured the volume-path pixels confirmed that
every pixel of the shape samples the volume, and that the sample varies across it.

`openskycli dds <path> --out <folder>` uploads a texture the way an effect shape does,
prints the uploaded type, size, and levels, and writes each slice of `--level` as a PNG.
`openskycli preview --mesh` of the barrier mesh draws the shape.
