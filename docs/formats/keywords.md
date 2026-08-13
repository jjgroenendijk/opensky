---
type: File Format
title: Keywords and actions (KYWD, AACT, KWDA)
description: Editor-id tag records, cross-plugin keyword lookup, and object keyword resolution.
tags: [format, plugin, records, keywords, actions, formid]
timestamp: 2026-08-13T00:00:00Z
---

# Keywords and actions (KYWD, AACT, KWDA)

`KYWD` records name the generic tags attached to objects. `AACT` records have the same
on-disk shape and name actions used as roots of idle trees. OpenSky decodes both because
they turn otherwise opaque FormID links into stable editor IDs.

References:

* UESP [KYWD](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/KYWD) and
  [AACT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AACT).
* xEdit `dev-4.1.6`, `Core/wbDefinitionsTES5.pas`, `wbRecord(KYWD, ...)` and
  `wbRecord(AACT, ...)`.

## Record layout

| field | type | decoded |
| --- | --- | --- |
| `EDID` | zstring | `editorID` |
| `CNAM` | uint8 RGBA | `editorColor`, an editor-only display aid |

xEdit declares `CNAM` required for both families. The owned vanilla install disagrees:
`KYWD 00013794` (`ActorTypeNPC`) and `AACT 00013009` (`ActionActivate`) each carry
only `EDID`. UESP also documents zero-sized AACT records with no `EDID`. Both fields are
therefore optional in the engine model. A malformed field is tallied and skipped without
discarding a usable sibling field; unknown fields are tallied separately.

## Keyword lists and resolution

Object records carry keywords as `KSIZ` followed by packed four-byte FormIDs in `KWDA`.
`KSIZ` remains advisory: OpenSky reads every whole FormID present in `KWDA` and ignores a
partial tail. See [record decoders](/formats/records.md) for the shared item-field layout.

`KeywordStore` is built above the load-order-wide
[RecordIndex](/formats/formid.md). It provides:

* lookup by `ResolvedFormID`;
* case-insensitive lookup by `EDID`;
* raw FormID resolution relative to the plugin containing the `KWDA`;
* a display string that uses the resolved editor ID and preserves a dangling raw FormID as
  hexadecimal text.

`KeywordList.contains(editorID:fromPlugin:using:)` compares resolved identities, not
hardcoded vanilla FormIDs. `displayStrings(fromPlugin:using:)` preserves `KWDA` order.
`RecordTextDump` uses the same seam for inventory summaries when a store and source plugin
are available.

## Verification

Synthetic tests cover both record decoders, wrong-type errors, truncated and unknown field
tallies, cross-plugin override precedence, case-insensitive editor-ID lookup, two-plugin
`KWDA` resolution, dangling display text, and decoded record/item summaries.

The env-gated sweep on 2026-08-13 pinned these Skyrim.esm lists:

* `IronSword`: `WeapMaterialIron`, `WeapTypeSword`, `VendorItemWeapon`;
* `ArmorIronCuirass`: `ArmorHeavy`, `ArmorMaterialIron`, `ArmorCuirass`,
  `VendorItemArmor`;
* `Gold001`: `VendorItemClutter`.

Across every `KWDA` in the active load order, 843 distinct resolved identities were
referenced; all 843 resolved to a decoded KYWD, leaving an unresolved tail of zero.
