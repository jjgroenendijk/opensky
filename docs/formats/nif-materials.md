---
type: File Format
title: NIF materials
description: BSLightingShaderProperty, BSEffectShaderProperty, BSShaderTextureSet, and
  NiAlphaProperty in Skyrim SE NIFs, and how texture paths are cleaned.
tags: [format, mesh, material, texture]
---

# NIF materials

A `BSTriShape` points at a shader property and an alpha property. These blocks start with only
the `NiObjectNET` fields (name, extra data, controller), not the `NiAVObject` fields. The
container is on the [NIF](/formats/nif.md) page.

Source: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml). Only the
Skyrim layouts (BS 83 and 100) are read. Fallout 4 and later move fields around.

## BSLightingShaderProperty

A quirk: for this block only, a uint32 shader type comes before the `NiObjectNET` name.
`nif.xml` declares it inside `NiObjectNET` with `onlyT=BSLightingShaderProperty`.

After the `NiObjectNET` fields. Fields in parentheses are read past, not kept:

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | Shader flags 1 | `SkyrimShaderPropertyFlags1` |
| uint32 | Shader flags 2 | Bit 4 is double-sided, so no culling |
| float x 2 | UV offset | |
| float x 2 | UV scale | |
| int32 | Texture set ref | `BSShaderTextureSet` |
| float x 4 | (Emissive color and multiplier) | |
| uint32 | (Clamp mode) | |
| float | Alpha | 1 is opaque |
| float | (Refraction) | |
| float | Glossiness | Specular power |
| float x 3 | Specular color | |
| float | Specular strength | |

The rest (lighting effects, and fields that depend on the shader type, such as environment map
scale, skin tint, parallax, and eye data) is not read. The block size bounds it.

## BSEffectShaderProperty

The material of an effect: glow, additive particles, unlit effects. Both Skyrim streams use the
same layout. There is no shader type before the name here.

After the `NiObjectNET` fields:

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | Shader flags 1 | `SkyrimShaderPropertyFlags1` |
| uint32 | Shader flags 2 | `SkyrimShaderPropertyFlags2` |
| float x 2 | UV offset | |
| float x 2 | UV scale | |
| SizedString | Source texture | The effect texture path |
| byte | Texture clamp mode | `TexClampMode` |
| byte | (Lighting influence) | |
| byte | (Env map min LOD) | |
| byte | (Unused) | |
| float | Falloff start angle | Cosine of the angle |
| float | Falloff stop angle | |
| float | Falloff start opacity | |
| float | Falloff stop opacity | |
| float x 4 | Base color | Emissive color with alpha |
| float | Base color scale | RGB multiplier |
| float | Soft falloff depth | Soft-particle edge fade |
| SizedString | Greyscale texture | Palette for greyscale-to-color |

At BS 83 and 100 there is no refraction power (Fallout 76 only), and no extra textures or
luminance fields (Fallout 4 and later).

Flag bits OpenSky uses:

| Flags | Bit | Meaning |
| --- | --- | --- |
| 2 | 4 | Double-sided |
| 2 | 0 | Z-buffer write. Clear means no depth write |
| 1 | 3 | Vertex alpha |
| 1 | 4, 5 | Greyscale to palette: color, alpha |
| 1 | 6 | Use falloff |
| 1 | 30 | Soft effect |
| 1 | 31 | Z-buffer test. `nif.xml` puts it in flags 1, not flags 2 |

## BSShaderTextureSet

A uint32 count, then one SizedString per slot:

| Slot | Texture |
| --- | --- |
| 0 | Diffuse (color) |
| 1 | Normal and gloss |
| 2 | Glow or skin |
| 3 | Height |
| 4 | Environment |
| 5 | Environment mask |
| 6 | Subsurface |
| 7 | Backlight |

Vanilla paths are messy: mixed case, `\` or `/`, with or without `textures\`, sometimes with a
leading `data\`. Some even hold the export machine's full path, such as
`textures/skyrimhd/build/pc/data/textures/...`. OpenSky cleans a path like this:

1. Lowercase it, and turn `\` into `/`.
2. Remove a leading `/` and `data/`.
3. Keep only the part after the last `textures/`, and make sure it starts with `textures/`.
4. An empty path means no texture.

Example: `Data\Textures\Clutter\Cup.dds` becomes `textures/clutter/cup.dds`.

A few vanilla paths point at textures that do not exist (`textures/err` markers and old effect
paths). Those get a placeholder texture.

## NiAlphaProperty

The `NiObjectNET` fields, then a uint16 of alpha flags and a uint8 threshold:

| Bits | Meaning |
| --- | --- |
| 0 | Blend on |
| 1-4 | Source blend mode |
| 5-8 | Destination blend mode |
| 9 | Alpha test on |
| 10-12 | Test function. 4 (greater) is the default |
| 13 | No sorter |

The threshold (0 to 255) is compared with the sampled alpha. Foliage cutouts use alpha test with
a threshold. Example: the thatch roof of `farmhouse01.nif` is double-sided with an alpha test at
0.5.
