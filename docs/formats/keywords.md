---
type: File Format
title: Keywords and actions (KYWD, AACT, KWDA)
description: Keyword and action records, and how object keyword lists resolve across plugins.
tags: [format, plugin, records, keywords, actions, formid]
---

# Keywords and actions (KYWD, AACT, KWDA)

A `KYWD` record is a named tag that objects carry. An `AACT` record has the same layout and
names an action, for example the root of an idle tree. Both turn a bare FormID into a stable
editor ID.

Sources: UESP [KYWD](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/KYWD) and
[AACT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AACT); xEdit `dev-4.1.6`,
`Core/wbDefinitionsTES5.pas`.

## Record layout

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `CNAM` | uint8 RGBA | Color used only by the editor |

xEdit says `CNAM` is required. The real install disagrees. `KYWD 00013794`
(`ActorTypeNPC`) and `AACT 00013009` (`ActionActivate`) have only `EDID`. UESP also lists
empty `AACT` records with no `EDID`. So both fields are optional in OpenSky.

## Keyword lists

An object stores its keywords as `KSIZ` (a count) and then `KWDA` (packed 4-byte FormIDs).
OpenSky trusts `KWDA`, not `KSIZ`. It reads every whole FormID in `KWDA` and ignores a short
tail. See [record decoders](/formats/records.md) for the shared item fields.

A FormID in `KWDA` is resolved relative to the plugin that holds the list (see
[FormID](/formats/formid.md)). Keyword checks compare resolved records, never hard-coded
vanilla FormIDs. A FormID that does not resolve is shown as hexadecimal text.

Examples from `Skyrim.esm`:

- `IronSword`: `WeapMaterialIron`, `WeapTypeSword`, `VendorItemWeapon`.
- `ArmorIronCuirass`: `ArmorHeavy`, `ArmorMaterialIron`, `ArmorCuirass`, `VendorItemArmor`.
- `Gold001`: `VendorItemClutter`.

In the vanilla load order, every FormID in every `KWDA` resolves to a `KYWD`.
