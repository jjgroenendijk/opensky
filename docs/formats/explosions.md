---
type: File Format
title: Explosion and debris records
description: Skyrim SE EXPL explosions with their four DATA sizes, and DEBR debris models.
tags: [format, plugin, magic]
---

# Explosion and debris records

`EXPL` is a blast: light, sound, force, damage, and what it leaves behind. `DEBR` is a
list of debris meshes an explosion or a destroyed object throws.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## EXPL

| Field | Type | Meaning |
| --- | --- | --- |
| `OBND` | 12 bytes | Bounds |
| `FULL` | lstring | Name |
| `MODL` | model group | The blast mesh |
| `EITM` | FormID | `ENCH` or `SPEL` applied to what the blast hits |
| `MNAM` | FormID | `IMAD` |
| `DATA` | 40 to 52 bytes | See below |
| `VMAD` | script data | Scripts |

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | FormID | `LIGH` |
| 4 | FormID | Sound 1 |
| 8 | FormID | Sound 2 |
| 12 | FormID | `IPDS` |
| 16 | FormID | Placed object |
| 20 | FormID | Spawn projectile |
| 24 | float | Force |
| 28 | float | Damage |
| 32 | float | Radius |
| 36 | float | Image-space radius |
| 40 | float | Vertical offset multiplier (44 bytes and up) |
| 44 | uint32 | Flags (48 bytes and up) |
| 48 | uint32 | Sound level: 0 loud, 1 normal, 2 silent, 3 very loud (52 bytes) |

Flags: 0x02 world orientation, 0x04 always knock down, 0x08 knock down by formula, 0x10
ignore line of sight, 0x20 push source only, 0x40 ignore image-space swap, 0x80 chain,
0x100 no controller vibration. The install has all four sizes over 277 records.

## DEBR

Each `DATA` field is one model: a uint8 percentage, a zstring path, and a uint8 flag
(0x01 has collision). A `MODT` right after it holds that model's texture hashes.

## Runtime

An explosion is set off by a projectile with an `EXPL` link, by an area spell at the struck
actor, or by the Effects panel. On detonation OpenSky:

1. Damages every actor whose capsule axis is within the radius. Damage falls linearly from
   the full `DATA` damage at the center to zero at the radius.
2. Plays sound 1 and sound 2 at the center.
3. Shows the `MODL` model at the center for 2 s.
4. Starts the `MNAM` image-space modifier. Its strength falls linearly from 1 at the center
   to 0 at the image-space radius, measured to the camera.
5. Places the placed object: a `HAZD` spawns a hazard, a `DEBR` throws debris.

A projectile with the alternate-trigger flag also detonates in the air: when its flight time
reaches the `PROJ` explosion timer, or when an actor other than the shooter comes within the
proximity distance. Such a projectile leaves no stuck arrow.

Simplifications:

- Force does not push actors or loose objects. It only sets the debris launch speed.
- The light, the impact data set, the spawn projectile, and the vertical offset are not used.
- Damage has no line-of-sight check and ignores the "ignore line of sight" flag.
- On the install, an `EXPL` placed object is a `HAZD` 4 times, an `ACTI` 11 times, an `EXPL`
  once, and another type 23 times. None is a `DEBR`. Placed objects of other types are
  counted and skipped.

Debris: each detonation or panel throw launches 6 pieces, picked from the `DEBR` models by
their percentage with a seeded random draw. Pieces fly outward and up, fall under gravity
(686 units/s²), spin, and are removed after 6 s. They have no collision.
