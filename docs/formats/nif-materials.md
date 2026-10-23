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
| uint32 | Shader flags 1 | `SkyrimShaderPropertyFlags1`; see "Draw state" and "Lit-surface terms" |
| uint32 | Shader flags 2 | `SkyrimShaderPropertyFlags2` |
| float x 2 | UV offset | |
| float x 2 | UV scale | |
| int32 | Texture set ref | `BSShaderTextureSet` |
| float x 3 | Emissive colour | |
| float | Emissive multiple | |
| uint32 | (Clamp mode) | |
| float | Alpha | 1 is opaque |
| float | Refraction strength | 0 to 1 |
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
| 14 sparkle snow | float x 4 sparkle parameters |
| 16 eye | float eye cube map scale, (float x 3 left and right eye centres) |

On the real install, Ralof's FaceGen head (`facegeom\skyrim.esm\0002bf9d.nif`) shows the
layout: the eye shape ends `1.0, 10.0, 1.3, -2.40, 7.57, 3.75, 2.40, 7.57, 3.75` (lighting
effects, cube map scale, two eye centres), and the hair shapes end with the tint colour
`0.635, 0.604, 0.447`.

A refraction shape bends the image behind it, such as the heat-haze dome in
`fireplacewood01burning.nif` (flags 1 `0x82418309`, texture `VaporTileNormal_n.dds`). Its
slot 0 texture is a normal map, so OpenSky loads it as the normal map and draws the shape
in the [refraction pass](/rendering/surface-shading.md).

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
| 5 | Skin tint | The actor's skin colour, when SLSF1 bit 21 (`FaceGen_RGB_Tint`) is set |

All 1684 vanilla type 5 shapes set bit 21, and no other type does.

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
| byte | Lighting influence | 0 to 255: the share of scene light an effect-lit shape takes |
| byte | (Env map min LOD) | |
| byte | (Unused) | |
| float | Falloff start angle | Cosine of the angle |
| float | Falloff stop angle | |
| float | Falloff start opacity | |
| float | Falloff stop opacity | |
| float x 4 | Base color | Emissive color with alpha |
| float | Base color scale | RGB multiplier |
| float | Soft falloff depth | World units over which a soft effect fades in |
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
| 1 | 22 | Own emit: the shape stays unlit, even with effect lighting |
| 1 | 26, 27 | Decal, dynamic decal |
| 1 | 29 | External emittance |
| 1 | 30 | Soft effect |
| 1 | 31 | Z buffer test. It is in flags 1, not flags 2 |
| 2 | 5 | Vertex colors |
| 2 | 17 | Weapon blood |
| 2 | 30 | Effect lighting |

`nif.xml` names bits 29, 30 (flags 1) and 30 (flags 2) without a description. OpenSky reads
them as the [shading below](#effect-shapes) says. On 2026-10-23 the vanilla meshes had 3796
effect blocks with soft effect (falloff depth 0.5 to 7000, median 32), 1750 with external
emittance, 1748 with effect lighting, and 310 with weapon blood. Lighting influence varies on
effect-lit blocks: 224 have 255, 100 have 191, 64 have 127. The 69 blocks with own emit never
set effect lighting too, so the own-emit rule is a reading of `nif.xml` ("will not absorb
light"), not a fact checked on data.

## BSWaterShaderProperty

A shape with this shader is a piece of placed water, such as a pool under a waterfall. OpenSky
does not decode the block. The shape gets the engine water-surface material, and the
[water pass](/rendering/water.md) draws it with the `WATR` look of its cell.

## BSSkyShaderProperty

The material of a sky mesh, such as the cloud dome, the stars, or a moon. After the
`NiObjectNET` fields: shader flags 1 and 2 (uint32 each), UV offset and UV scale
(float32 x 2 each), the source texture (`SizedString`), and the sky object type (uint32,
`nif.xml` `SkyObjectType`: 0 texture, 1 sun glare, 2 sky, 3 clouds, 5 stars, 7 moon and
stars mask).

OpenSky draws a sky shape unlit and double-sided, with its texture, UV transform, and
vertex colours and alpha. Every type but the sky dome itself blends. The weather sky uses
its own pipeline; this material is what the mesh preview and any other mesh path see.

## BSShaderTextureSet

A uint32 count, then one SizedString per slot. Slot 0 is diffuse, slot 1 normal and
specular mask (in alpha). Slots 2 to 7 are glow or light mask, detail or height,
environment cube map, environment mask, face tint or inner layer, and back light or
specular map. On a FaceGen shape, slot 3 is the detail map and slot 6 the face tint.

## Draw state

These flags change how a shape draws, not how it is lit. The first set of rows come from
`nif.xml`. The counts are over every lit shape in the vanilla archives.

| Flag | Meaning in OpenSky |
| --- | --- |
| SLSF1 bit 31 `ZBuffer_Test` | Depth test. Cleared: the shape draws over everything |
| SLSF2 bit 0 `ZBuffer_Write` | Depth write. 8281 shapes clear it, nearly all with an alpha property |
| SLSF1 bits 26, 27 `Decal`, `Dynamic_Decal` | Depth pulled toward the eye, as in the decal pass. Mostly hair cards and skin overlays |
| SLSF1 bit 9 `Cast_Shadows` | Casts a sun shadow |
| SLSF1 bit 8 `Recieve_Shadows` | Takes the sun shadow |
| SLSF2 bit 7 `Assume_Shadowmask` | Takes the sun shadow too. The game reads it from its screen shadow mask, OpenSky from the shadow map |
| SLSF2 bits 1, 2, 31 LOD | Terrain and object LOD: no shadows and no point lights |
| SLSF1 bit 19 `Screendoor_Alpha_Fade` | Alpha becomes a 4 x 4 dither of whole pixels instead of a blend |
| SLSF1 bit 3 `Vertex_Alpha` | Without it the vertex alpha is ignored |
| SLSF2 bit 5 `Vertex_Colors` | Without it the vertex colour is ignored |
| SLSF1 bit 15 `Refraction` | Drawn in the refraction pass: the scene behind, bent by the slot 0 normal map |
| SLSF1 bit 16 `Fire_Refraction` | With bit 15, the normal map scrolls upward, as heat over a fire |

`nif.xml` describes bit 3 as "Enables using alpha component of vertex colors". 40424 vanilla
shapes store a vertex alpha below 1 without the bit, among them 6709 hair shapes and every
terrain LOD shape. With bit 29 (tree animation) the alpha is wind weight and is ignored too.
No vanilla shape stores a vertex colour below 0.95 without bit 5.

`BSEffectShaderProperty` shapes read the same depth and decal bits. The "Material depth and
decal flags" switch in Surface Shading turns the depth, decal, and dither flags off.

## Flags with no read

OpenSky already behaves as these flags ask, so it does not read them:

| Flag | Why no read is needed |
| --- | --- |
| SLSF1 bit 1 `Skinned` | The skin instance decides skinning. Every vanilla shape with a skin instance sets the bit, and no other shape does |
| SLSF1 bit 25 `Remappable_Textures` | Alternate textures (`MODS`) apply to any shape. 2311 of 2322 vanilla swaps target a shape with the bit. The other 11 are the ash-covered logs of Dragonborn, whose swap is wanted |
| SLSF2 bit 3 `No_Fade` | OpenSky does not fade objects out with distance, so every shape behaves as if it set the bit |
| SLSF2 bit 28 `Unused02` | `nif.xml` marks it unused |

The same holds for `Skinned` and `No_Fade` on a `BSEffectShaderProperty`.

The Fallout 3 flags in `nif.xml` describe bit 16 as "switches on refraction power/period",
and the period as the "rate of texture movement for refraction shader". Skyrim blocks have
no period field, so OpenSky picks the scroll rate. 51 vanilla shapes set bit 16 without bit
15, such as the flame atronach's body. With nothing to scroll they draw as plain lit shapes.
The block's refraction strength (0 to 1, "the amount of distortion") scales the bend.

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
| FaceGen detail | Type 4 and SLSF1 bit 10 | Slot 3 |
| Parallax | Type 3 and SLSF1 bit 11 | Slot 3 height map |
| Environment | Type 1 and SLSF1 bit 7, type 16 and SLSF1 bit 17, or multi-layer | Slot 4 cube map |
| Environment mask | Environment | Slot 5; otherwise the normal alpha |
| Multi-layer parallax | Type 11 and SLSF2 bit 24 | Slot 6 inner layer |
| Tint colour | Type 5 or 6 | None; the tail colour |
| Hair soft light | SLSF1 bit 18 | None; caps the direct light |
| Anisotropic specular | SLSF2 bit 21 | None; the highlight follows the strand |
| Reflection lit with the surface | Environment and SLSF2 bit 15 | Without the bit the reflection adds unlit |
| External emittance | SLSF1 bit 29 | None; the reference's `XEMI` light or region colour replaces the emissive colour |
| Sparkle | Type 14 | None; the tail parameters |
| Landscape noise | Type 18 | `textures\terrain\noise.dds`, which the shape does not name |

nif.xml describes bit 18 as "keeps from going too bright under lights (hair shader only)".
The 406 vanilla shapes with bit 29 are mostly lit windows (type 2), and their own emissive
colour is black, so without the reference colour they do not glow.

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

### Effect shapes

A mesh shape with an effect shader, such as a smoke disc, a fire card, or waterfall foam,
draws with the effect's source texture, UV transform, double-sided flag, base color,
falloff, and greyscale palette, plus its `NiAlphaProperty`. The palette lookup follows the
open-source NifSkope effect shader (`sk_effectshader.frag`):

- Palette color: the color at (texture green, vertex green x falloff x base red).
- Palette alpha: the alpha at (texture alpha, vertex alpha x falloff x base alpha squared).
- Falloff: `smoothstep(stop, start, |N . V|)` mixes the stop opacity into the start opacity.

Vanilla palettes are 2D, for example `textures\effects\gradients\GradWhiteWater.dds` is
512 x 128, so the second coordinate matters.

The flags then change the result. Neither NifSkope nor `nif.xml` gives these rules, so they
are OpenSky's reading of the Creation Kit wiki
([Lights and FX tutorial](https://ck.uesp.net/wiki/Bethesda_Tutorial_Lights_and_FX),
[Weather](https://ck.uesp.net/wiki/Weather)):

- Effect lighting: the color is multiplied by the scene light at the shape, mixed with 1 by
  the lighting influence. The light is the ambient, the six-axis ambient, the sun, and the
  nearby point lights, on the side of the shape that faces the eye. The tutorial shows mist
  that "picks up the light's coloration" near a light. Near a shadow-casting light, the mist
  "inherits the directional/ambient light of the cell, but not the light", so a light with
  a shadow type in its `LIGH` flags does not light an effect shape.
- External emittance: when the placed reference has an `XEMI` emittance, that color
  replaces the scene light. The tutorial says emittance "will prevent the mist from being
  affected by any other light". `XEMI` names a `LIGH` or a `REGN`. A light gives its
  color. A region gives the `Effect Lighting` color of its weather at the current hour
  ([Reference](https://ck.uesp.net/wiki/Reference)). The game keeps a weather per region;
  OpenSky runs one, so a region takes the active weather when its `RDWT` list holds it, else
  its most likely weather. Particle systems take the emittance of their reference too.
- Soft effect: the alpha fades in over the soft falloff depth in front of the scene behind
  the shape, so a smoke card shows no hard line where it crosses the ground.
- Weapon blood: the shape draws only while its weapon is bloody
  ([visual effects](/rendering/visual-effects.md)). Vanilla weapons, and even forks and
  knives, hold such a shape with `textures\blood\BloodEdge01.dds`.

An additive shape (`NiAlphaProperty` with destination factor `ONE`) adds light to the frame.
Glow cards are additive. So is `wrlodwindowglow01.nif`, the window glow of the low-detail
Whiterun that the `WhiterunLODlights` reference places in Tamriel. Its `XEMI` emittance
(`FXLightRegionInvertWindowWhiterun`) darkens it by day. Source factor `ONE` adds the color
as it is; any other source factor is read as `SRC_ALPHA`. An effect shape with no source
texture is skipped, because the static path has no look for it.

An effect block that does not decode keeps the fallback material.
