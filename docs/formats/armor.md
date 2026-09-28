---
type: File Format
title: Armor records (ARMO, ARMA, OTFT)
description: ARMO, ARMA, and OTFT layouts, the body template slot mask, and armor draw
  priority.
tags: [format, plugin, actors, armor, outfit]
---

# Armor records

An ARMO is one piece of armor or clothing. Its ARMA armatures hold the models that are drawn
on a body. An OTFT is a default outfit. The NPC_ and RACE records that name them are on
[actor records](/formats/actors.md). [Actor resolution](/engine/actor-resolution.md)
explains how OpenSky picks and draws the parts.

Sources: UESP "Skyrim Mod:Mod File Format" pages `/ARMO`, `/ARMA`, and `/OTFT`
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>), xEdit dev-4.1.6
`wbDefinitionsTES5.pas`, the Creation Kit wiki page "ArmorAddon", and NifTools `nif.xml`
`BSDismemberBodyPartType` for biped slot numbers.

All integers and floats are little-endian.

## ARMO

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | name |
| `RNAM` | FormID | race, usually `0x19` DefaultRace |
| `BOD2`/`BODT` | struct | equip slots |
| `MODL` | FormID | one `ARMA`; repeated |

On ARMO, `MODL` is a 4-byte ARMA FormID, not a path. `SkinNaked` has 25 of them. `MOD2` and
`MOD4` are the ground and inventory models. Weapon and armor enchantment fields are on
[record decoders](/formats/item-records.md).

## ARMA

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `BOD2`/`BODT` | struct | slots this armature covers |
| `RNAM` | FormID | primary race |
| `DNAM` | 12 bytes | draw priority and weapon adjust |
| `MODL` | FormID | extra race, for example a vampire variant; repeated |
| `MOD2`/`MOD3` | zstring | male and female third-person model |
| `MOD4`/`MOD5` | zstring | male and female first-person model |

`NAM0` to `NAM3` are texture swaps. Many ARMAs have a male model only, and both genders wear
it (`StormCloakBootsAA`). First-person models are rare: of the ARMAs for vanilla iron armor,
only the torso and hands have one.

`DNAM`: `0x00` uint8 male priority, `0x01` uint8 female priority, `0x02` 4 bytes (xEdit:
weight-slider flags; UESP: one unknown uint32), `0x06` uint8 detection sound value, `0x07`
unused, `0x08` float32 weapon adjust.

Priority is a draw order, not a rule to hide parts. The Creation Kit wiki says priority "is
used to determine the order of the ArmorAddons. The base naked body (for all parts) is
always 0." The install confirms it. `OrcishCuirassAA` covers slots `0x114` (body, forearms,
calves) at priority 5. `OrcishBootsAA` covers `0x180` (feet, calves) at priority 10. Both
cover the calves. If the higher priority hid the other part, the boots would remove the
cuirass. The game draws both.

## OTFT

`INAM` is a packed array of FormIDs (size / 4 entries). Entries can be `ARMO` or `LVLI`;
guard outfits nest LVLI bundles. A size that is not a multiple of 4 is malformed.

## Body template

`BOD2` and `BODT` start with a uint32 slot mask: bit N is biped slot 30 + N (`SBP_30_HEAD`
to `SBP_61_FX01` in `nif.xml`). `BOD2` (8 bytes) adds a uint32 armor type. `BODT` (12
bytes) adds uint32 general flags, then armor type. An 8-byte `BODT` has only one of the two
words, so the armor type is unknown. ARMA at form version 40 writes 12-byte `BODT`. ARMO
and RACE at form version 44 write 8-byte `BOD2`.
