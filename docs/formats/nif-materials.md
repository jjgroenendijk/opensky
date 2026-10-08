---
type: File Format
title: NIF materials (Skyrim SE)
description: BSLightingShaderProperty, BSEffectShaderProperty, BSShaderTextureSet, and
  NiAlphaProperty layouts, and texture path rules.
tags: [format, mesh, material, texture, rendering]
---

# NIF materials

A `BSTriShape` links a shader property and an alpha property (see [NIF](/formats/nif.md)).
These blocks start with the `NiObjectNET` fields only (name, extra data, controller), not
the full node fields.

Reference: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml).
Only the Skyrim layouts (streams 83 and 100) are read. Fallout 4 and later move fields.

## BSLightingShaderProperty

A quirk: for this block only, a uint32 shader type comes before the `NiObjectNET` name.
`nif.xml` declares it inside `NiObjectNET` with `onlyT=BSLightingShaderProperty`. After the
`NiObjectNET` fields (fields in brackets are read but not kept):

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | Shader flags 1 | `SkyrimShaderPropertyFlags1` |
| uint32 | Shader flags 2 | Bit 4: double-sided, so no culling |
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

The fields after specular strength (lighting effects, and per-shader-type fields such as
environment map scale, skin tint, parallax, and eye data) are not read. The block size
bounds them.

## BSEffectShaderProperty

The material of an effect: glow, additive particles, unlit effects. Both Skyrim streams use
the same layout. There is no shader type before the name here. After the `NiObjectNET`
fields:

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | Shader flags 1 | `SkyrimShaderPropertyFlags1` |
| uint32 | Shader flags 2 | `SkyrimShaderPropertyFlags2` |
| float x 2 | UV offset | |
| float x 2 | UV scale | |
| SizedString | Source texture | Effect texture path |
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
| float | Soft falloff depth | Soft particle edge fade |
| SizedString | Greyscale texture | Palette for greyscale-to-color |

At streams 83 and 100 there is no refraction power (`nif.xml` has it only for Fallout 76),
and no environment, normal, or mask textures or luminance fields (Fallout 4 and later).

Flag bits OpenSky uses:

| Flags | Bit | Meaning |
| --- | --- | --- |
| 2 | 4 | Double-sided |
| 2 | 0 | Z buffer write. Cleared means no depth write |
| 1 | 3 | Vertex alpha |
| 1 | 4, 5 | Greyscale to palette color, alpha |
| 1 | 6 | Use falloff |
| 1 | 30 | Soft effect |
| 1 | 31 | Z buffer test. It is in flags 1, not flags 2 |

## BSWaterShaderProperty

A shape with this shader is a piece of placed water, such as a pool under a waterfall. OpenSky
does not decode the block. The shape gets the engine water-surface material, and the
[water pass](/rendering/water.md) draws it with the `WATR` look of its cell.

## BSShaderTextureSet

A uint32 count, then one SizedString per slot. Slot 0 is diffuse, slot 1 normal and gloss.
Slots 2 to 7 are glow or skin, height, environment, environment mask, subsurface, and back
light. OpenSky keeps them but uses only slots 0 and 1.

Vanilla paths vary a lot: mixed case, `\` or `/`, with or without `textures\`, and
sometimes a leading `data\`. Some are absolute paths from the exporter's machine, for
example `textures/skyrimhd/build/pc/data/textures/...`. OpenSky makes a VFS key like this:

1. Lowercase, and `\` becomes `/`.
2. Remove a leading `/` and `data/`.
3. Cut everything before the last `textures/`.
4. Add `textures/` in front if it is missing.
5. An empty path gives no texture.

Almost all vanilla diffuse paths resolve. About 200 name textures that do not exist
(`textures/err` markers, old effect paths) and get the placeholder.

## NiAlphaProperty

The `NiObjectNET` fields, then uint16 alpha flags and a uint8 threshold (`nif.xml`
`AlphaFlags`):

| Bits | Meaning |
| --- | --- |
| 0 | Blend on |
| 1-4 | Source blend mode (`AlphaFunction`) |
| 5-8 | Destination blend mode (`AlphaFunction`) |
| 9 | Alpha test on |
| 10-12 | Test function. 4 (greater) is the default |
| 13 | No sorter |

The threshold (0 to 255) is compared with the sampled alpha. Foliage cutouts use alpha test
with a threshold. For example, the thatch roof of `farmhouse01.nif` is double-sided with
alpha test at 0.5.

## Engine material

Each (shader, alpha) pair becomes one material: texture keys, UV transform, alpha,
glossiness, specular, double-sided, and alpha blend and test. Water and sky shaders get a
plain fallback material, untextured but drawn. Effect shaders used by particles go to the
particle path instead (see [NIF particle systems](/formats/nif-particles.md)).

A mesh shape with an effect shader, such as a smoke disc, a fire card, or waterfall foam,
draws unlit with the effect's source texture, UV transform, double-sided flag, base color,
falloff, and greyscale palette, plus its `NiAlphaProperty`. The palette lookup follows the
open-source NifSkope effect shader (`sk_effectshader.frag`):

- Palette color: the color at (texture green, vertex green x falloff x base red).
- Palette alpha: the alpha at (texture alpha, vertex alpha x falloff x base alpha squared).
- Falloff: `smoothstep(stop, start, |N . V|)` mixes the stop opacity into the start opacity.

Vanilla palettes are 2D, for example `textures\effects\gradients\GradWhiteWater.dds` is
512 x 128, so the second coordinate matters. Two kinds of effect shape are skipped,
because the static path cannot draw them:

- An effect shape with no source texture.
- An additive one: `NiAlphaProperty` blends with destination factor `ONE`, so it only adds
  light. Glow cards are additive. So is `wrlodwindowglow01.nif`, the window glow of the
  low-detail Whiterun that the `WhiterunLODlights` reference places in Tamriel. Its `XEMI`
  emittance (`FXLightRegionInvertWindowWhiterun`) darkens it by day.

An effect block that does not decode keeps the fallback material.
