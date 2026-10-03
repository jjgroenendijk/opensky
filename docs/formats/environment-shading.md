---
type: File Format
title: Environment shading records
description: Skyrim SE SPGD precipitation, VOLI volumetric lighting and MATO directional material records.
tags: [format, plugin, rendering, weather]
---

# Environment shading records

Three small records shape the look of the world around the player. `SPGD` is rain and
snow particles. `VOLI` is volumetric lighting (god rays through fog). `MATO` is the snow
or moss layer that covers the top of statics.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## SPGD

`DATA` is 40 bytes in the original game and 48 bytes in SE; the install has both (18
records). `ICON` is the particle texture.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | float | Gravity velocity |
| 4 | float | Rotation velocity |
| 8 | 2 floats | Particle size X, Y |
| 16 | float | Center offset min |
| 20 | float | Center offset max |
| 24 | float | Initial rotation range |
| 28 | 2 uint32 | Subtexture count X, Y |
| 36 | uint32 | Type: 0 rain, 1 snow |
| 40 | uint32 | Box size (48 bytes only) |
| 44 | float | Particle density (48 bytes only) |

## VOLI

Every member is its own float field: `CNAM` intensity, `DNAM` custom color contribution,
`ENAM` `FNAM` `GNAM` red, green, blue, `HNAM` density contribution, `INAM` density size,
`JNAM` density wind speed, `KNAM` density falling speed, `LNAM` phase function
contribution, `MNAM` phase function scattering, `NNAM` sampling range factor. A weather
links four of them, one per time of day, through `WTHR HNAM`.

## MATO

| Field | Type | Meaning |
| --- | --- | --- |
| `MODL` | model group | Material mesh |
| `DNAM` | bytes | Property data, not decoded by xEdit, kept raw |
| `DATA` | 28 to 52 bytes | See below |

`DATA` holds falloff scale, falloff bias, noise UV scale, material UV scale, and a
projection vector (3 floats). Later versions add a normal dampener (32 bytes), a
single-pass color and flag (48 bytes), and a snow flag (52 bytes). The install has all
four sizes over 74 records.

## Precipitation mapping

The rain and snow volumes are tuned by hand to look right with the vanilla records
`RainParticles` (type 0, gravity 675, size 0.35 by 2, density 1) and `SnowParticlesMed`
(type 1, gravity 100, size 1 by 1, density 3). The `SPGD` that the heaviest weather of the
blend names in `WTHR MNAM` is read as a ratio to its anchor:

| Volume value | Ratio |
| --- | --- |
| Fall speed | Gravity velocity over the anchor's |
| Particle size | Square root of the particle area over the anchor's area |
| Density (spawn rate) | Particle density over the anchor's |

Each ratio is clamped to 0.25 to 4. Type 0 tunes rain and type 1 tunes snow. A weather with
no `SPGD`, a record without `DATA`, or another type keeps the hand-tuned values. A faster fall
also shortens each particle's life, so the volume keeps its height.
