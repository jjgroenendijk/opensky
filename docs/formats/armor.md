---
type: File Format
title: Armor records
description: ARMO and ARMA layouts, the body template and biped slots, and why armature
  priority is a draw order and not a visibility rule.
tags: [format, esm, actors, armor, armature, biped]
---

# Armor records (ARMO, ARMA)

`ARMO` is one piece of armor or clothing. `ARMA`, an armature, says how the piece looks on a
body: one model per gender and the races it fits. How OpenSky picks and draws them is on the
[actor appearance](/engine/actor-appearance.md) page.

Sources: UESP [ARMO](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ARMO) and
[ARMA](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ARMA); xEdit `dev-4.1.6`; the
Creation Kit wiki "ArmorAddon" page; NifTools `nif.xml` `BSDismemberBodyPartType` for slot
numbers.

## ARMO fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `RNAM` | FormID | Race filter. Usually `DefaultRace` (`0x19`) |
| `BOD2`, `BODT` | struct | Body template: the slots the piece fills |
| `MODL` | FormID, repeats | One `ARMA` each |

On `ARMO`, `MODL` is a 4-byte `ARMA` FormID, not a path. Example: `SkinNaked` has 25 of them. A
`MODL` of another size is skipped. The `MOD2` and `MOD4` paths on an `ARMO` are the models for
the ground and the inventory. They are not worn models. The enchantment is on the
[enchantment records](/formats/enchantment-records.md) page.

## ARMA fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `BOD2`, `BODT` | struct | The slots the armature covers |
| `RNAM` | FormID | Primary race |
| `DNAM` | 12 bytes | Priorities and weapon adjust. Below |
| `MODL` | FormID, repeats | Other races it fits, such as vampire variants |
| `MOD2` | zstring | Male model, third person |
| `MOD3` | zstring | Female model, third person |
| `MOD4` | zstring | Male model, first person |
| `MOD5` | zstring | Female model, first person |

Texture swaps (`NAM0` to `NAM3`) and `MODT` hashes are not read.

First-person models are rare. In vanilla iron armor only the torso and hand armatures have
one. If neither gender has a first-person model, OpenSky uses none. It does not fall back to
the third-person model, because that model is skinned to bones the first-person skeleton does
not have.

## Body template and biped slots

Both forms start with a uint32 slot bit field. Bit N is biped slot 30 + N, numbered as in
`nif.xml` `BSDismemberBodyPartType` (`SBP_30_HEAD` to `SBP_61_FX01`).

| Form | Layout |
| --- | --- |
| `BOD2`, 8 bytes | Slots, armor type |
| `BODT`, 12 bytes | Slots, general flags, armor type |
| `BODT`, 8 bytes | Slots, then one word that could be either. Armor type is left empty |

`ARMA` records at form version 40 use a 12-byte `BODT`. `ARMO` and `RACE` at version 44 use an
8-byte `BOD2`.

## ARMA DNAM (12 bytes)

```text
00 uint8   male draw priority
01 uint8   female draw priority
02 4 bytes weight slider flags (xEdit), or one unknown uint32 (UESP)
06 uint8   detection sound value
07 1 byte  unused
08 float32 weapon adjust
```

UESP and xEdit name bytes 2 to 5 differently, but agree on every offset. OpenSky reads the two
priorities and the weapon adjust. A short `DNAM` is read as far as it goes. A missing priority
reads the same as no `DNAM`.

## Priority is a draw order

The Creation Kit wiki: priority "is used to determine the order of the ArmorAddons. The base
naked body (for all parts) is always 0. The armor for a torso would then be 5 and gloves that
you want to draw over the ends of sleeves, for example, would be 10."

Vanilla data proves it is not a visibility rule:

```text
OrcishCuirassAA  slots 0x114 (body, forearms, calves)  priority 5
OrcishBootsAA    slots 0x180 (feet, calves)            priority 10
```

Both cover the calves, and the boots have the higher priority. If priority hid the lower
armature, Orcish boots would remove the whole Orcish cuirass. The game draws both. So OpenSky
sorts worn parts by priority, lowest first, and hides nothing because of it. Hiding is the job
of the equipped slot mask.

The sort covers the whole worn set, so it also orders armatures inside one `ARMO`. Example:
`ClothesMonkRobesHooded` lists `MonkRobesAA` (priority 15) before `MonkHoodAA` (priority 10).
OpenSky draws the hood first. The sort is stable: equal priorities keep their order, so the
result is the same every run.
