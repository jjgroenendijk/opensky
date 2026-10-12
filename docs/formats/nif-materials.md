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
| uint32 | Shader flags 1 | Bit 15: refraction, so the shape is skipped |
| uint32 | Shader flags 2 | Bit 4: double-sided, so no culling. Bit 29: tree animation |
| float x 2 | UV offset | |
| float x 2 | UV scale | |
| int32 | Texture set ref | `BSShaderTextureSet` |
| float x 3 | Emissive colour | |
| float | Emissive multiple | |
| uint32 | (Clamp mode) | |
| float | Alpha | 1 is opaque |
| float | (Refraction) | |
| float | Glossiness | Specular power |
| float x 3 | Specular colour | |
| float | Specular strength | |
| float | Lighting effect 1 | Soft-light wrap |
| float | Lighting effect 2 | Rim-light power |

Then a tail that depends on the shader type. A block that ends early keeps the defaults.

| Type | Tail |
| --- | --- |
| 1 environment map | float environment map scale |
| 5 skin tint | float x 3 skin tint colour |
| 6 hair tint | float x 3 hair tint colour |
| 7 parallax occlusion | (float max passes, float scale) |
| 11 multi-layer parallax | float inner thickness, float refraction scale, float x 2 inner texture scale, float environment strength |
| 14 sparkle snow | (float x 4 sparkle parameters) |
| 16 eye | float eye cube map scale, (float x 3 left and right eye centres) |

On the real install, Ralof's FaceGen head (`facegeom\skyrim.esm\0002bf9d.nif`) shows the
layout: the eye shape ends `1.0, 10.0, 1.3, -2.40, 7.57, 3.75, 2.40, 7.57, 3.75` (lighting
effects, cube map scale, two eye centres), and the hair shapes end with the tint colour
`0.635, 0.604, 0.447`.

A refraction shape bends the image behind it, such as the heat-haze dome in
`fireplacewood01burning.nif` (flags 1 `0x82418309`, texture `VaporTileNormal_n.dds`). Its
texture is a normal map. OpenSky has no refraction pass, so it does not draw the shape.

A shape with the tree animation flag, such as a pine branch in `treepineforestdead01.nif`
(flags 2 `0x22008031`), stores its wind weight in the vertex alpha. OpenSky sets that alpha
to 1, so it does not cut the branch away.

Which flag and slot turn on each lit-surface term is in "Lit-surface terms" below. How the
renderer shades them is in [surface shading](/rendering/surface-shading.md).

## Skin and face tints

The shader type (`nif.xml` `BSLightingShaderType`) decides two tints. The blend rules
follow NifSkope's open shaders (`sk_msn.frag`, and the slot numbers in `renderer.cpp`).

| Type | Name | Tint |
| --- | --- | --- |
| 4 | FaceGen | Texture slot 6, the FaceGen tint, overlay-blended over the diffuse |
| 5 | Skin tint | The actor's skin colour multiplies the diffuse |

Overlay: where the base is below 0.5 the result is `2 * base * tint`, otherwise
`1 - 2 * (1 - base) * (1 - tint)`. A tint of 0.5 leaves the base as it is. The game blends in
gamma space, so OpenSky converts the linear samples to gamma 2.2 for the blend. A baked
FaceGen head, such as `facegeom\skyrim.esm\<id8>.nif`, names its tint at slot 6 as
`facegendata\facetint\skyrim.esm\<id8>.dds` ([FaceGen paths](/formats/actors.md)).

The skin colour is the `NPC_ QNAM` texture lighting colour, a Traits-tab field. OpenSky
multiplies it into the vertex colours of the skin-tint shapes only, so the armour shapes in
the same model keep their colour. Ralof's is `0.776, 0.690, 0.659`; over all 5118 vanilla
NPCs the values run from 0 to 1.

The type 5 and 6 tails also store a tint colour. The shader multiplies the albedo by it. An
actor's own colour replaces it: `QNAM` on a skin shape, and the hair colour on an assembled
hair head part. A baked FaceGen head already holds the actor's hair colour in its hair
shapes, as Ralof's does.

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

A uint32 count, then one SizedString per slot. Slot 0 is diffuse, slot 1 normal and
specular mask (in alpha). Slots 2 to 7 are glow or light mask, detail or height,
environment cube map, environment mask, face tint or inner layer, and back light or
specular map. On a FaceGen shape, slot 3 is the detail map and slot 6 the face tint.

## Lit-surface terms

A term is on only when its texture slot names a texture. The rules follow NifSkope's
`glproperty.cpp`. SLSF1 and SLSF2 are shader flags 1 and 2.

| Term | Condition | Texture |
| --- | --- | --- |
| Model-space normals | SLSF1 bit 12 | Slot 1 |
| Specular | SLSF1 bit 0 | Normal alpha, or slot 7 on a model-space shape without back light |
| Emissive | SLSF1 bit 22 | None; colour times multiple |
| Glow map | Type 2 and SLSF2 bit 6 | Slot 2 scales the emissive colour |
| Soft light | SLSF2 bit 25 | Slot 2 light mask |
| Rim light | SLSF2 bit 26 | Slot 2 light mask |
| Back light | SLSF2 bit 27 | Slot 7 |
| FaceGen detail | Type 4 | Slot 3 |
| Parallax | Type 3 and SLSF1 bit 11 | Slot 3 height map |
| Environment | Type 1 and SLSF1 bit 7, type 16 and SLSF1 bit 17, or multi-layer | Slot 4 cube map |
| Environment mask | Environment | Slot 5; otherwise the normal alpha |
| Multi-layer parallax | Type 11 and SLSF2 bit 24 | Slot 6 inner layer |
| Tint colour | Type 5 or 6 | None; the tail colour |

Ralof's head (type 4, flags 1 `0x82401703`, flags 2 `0x02008021`) uses model-space normals,
specular from slot 7, soft light with the slot 2 mask, the slot 3 detail map, and the slot 6
face tint. His body and hands (type 5) use the same terms without the face maps.

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
glossiness, specular, double-sided, alpha blend and test, and the lit-surface terms with
their textures and constants. Water and sky shaders get a
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
