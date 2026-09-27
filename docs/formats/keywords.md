---
type: File Format
title: Keywords and actions (KYWD, AACT, KWDA)
description: Keyword and action records, and how a KWDA list on an object resolves to
  keyword editor IDs.
tags: [format, plugin, records, keywords, actions, formid]
---

# Keywords and actions (KYWD, AACT, KWDA)

A `KYWD` record is a tag that objects carry, for example `WeapTypeSword`. An `AACT` record
has the same layout and names an action, for example `ActionActivate`. Idle animation trees
use actions as roots. Both records turn a FormID into a readable editor ID.

References: UESP [KYWD](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/KYWD) and
[AACT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AACT); xEdit `dev-4.1.6`,
`Core/wbDefinitionsTES5.pas`, `wbRecord(KYWD, ...)` and `wbRecord(AACT, ...)`.

## Record layout

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `CNAM` | 4 x uint8 RGBA | Color shown in the Creation Kit only |

xEdit says `CNAM` is required. The vanilla install shows it is not: `KYWD 00013794`
(`ActorTypeNPC`) and `AACT 00013009` (`ActionActivate`) have only `EDID`. UESP also
describes empty AACT records with no `EDID`. So OpenSky treats both fields as optional.

## Keyword lists on objects

An object record lists its keywords in two fields. `KSIZ` is the count. `KWDA` is a packed
list of 4-byte FormIDs. OpenSky trusts `KWDA`, not `KSIZ`: it reads every whole FormID in
`KWDA` and ignores a partial tail. See [record decoders](/formats/records.md) for the other
item fields.

A FormID in `KWDA` is relative to the plugin that holds the `KWDA`. See
[FormID resolution](/formats/formid.md). Compare keywords by resolved identity or editor ID,
never by a hardcoded vanilla FormID.

Examples from `Skyrim.esm`:

- `IronSword`: `WeapMaterialIron`, `WeapTypeSword`, `VendorItemWeapon`.
- `ArmorIronCuirass`: `ArmorHeavy`, `ArmorMaterialIron`, `ArmorCuirass`, `VendorItemArmor`.
- `Gold001`: `VendorItemClutter`.

On the vanilla load order, every FormID in every `KWDA` resolves to a `KYWD` record.
