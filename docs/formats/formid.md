---
type: File Format
title: FormID and TES4 plugin header
description: TES4 header layout, master lists, and how raw FormIDs resolve to (plugin, objectID).
tags: [format, plugin, esm, formid, records]
timestamp: 2026-07-09T00:00:00Z
---

# FormID + TES4 plugin header, Skyrim SE

Every record carries a 32-bit FormID (offset 0x0C of the record header, see
[ESM container](/formats/esm.md)). Raw FormIDs are file-relative: their top
byte only means something together with the owning plugin's master list from
its TES4 header. This page covers both.

References: UESP "Skyrim Mod:Mod File Format" — TES4 record
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>), UESP "Skyrim Mod:FormIDs"
(<https://en.uesp.net/wiki/Skyrim_Mod:FormIDs>).
Impl: `opensky/Formats/ESM/PluginHeader.swift`, `FormID.swift`.

## TES4 record fields

First record of every plugin. Fields OpenSky decodes (`PluginHeader`):

| field | type            | meaning                                      |
| ----- | --------------- | -------------------------------------------- |
| HEDR  | 12 bytes, req'd | file stats, layout below                     |
| CNAM  | zstring         | author (opt)                                 |
| SNAM  | zstring         | description (opt)                            |
| MAST  | zstring         | master file name; one per master, file order |
| DATA  | uint64          | follows each MAST, always 0 — skipped        |

HEDR: float32 version (1.71 = SSE), int32 recordCount, uint32 nextObjectID.

Skipped as unneeded: ONAM (overridden-form list), INTV, INCC, modder-added
fields. Strings are windows-1252 zstrings. Missing HEDR ->
`ESMError.malformed`. Record flags of the TES4 record carry plugin-level
bits: 0x1 ESM, 0x80 localized (lstring tables), 0x200 ESL.

HEDR recordCount is CK bookkeeping and includes groups; traversal never
trusts it (Skyrim.esm says 920 181; walking finds 869 687 records +
50 494 groups).

## FormID layout

`0xIIOOOOOO`: top byte II = master index, low 24 bits = object ID.

Within a plugin file, the master index points into THAT plugin's MAST list:

* index < masters.count -> record/reference lives in that master.
* index == masters.count -> defined by this plugin itself (normal encoding
  for own records).
* index > masters.count -> malformed; clamped to the plugin itself, matching
  xEdit's handling.
* FormID 0x00000000 -> null, "no reference" sentinel, resolves to nil.

Runtime load-order indices (what the game shows in console) are a different
numbering — they depend on the user's full load order. OpenSky models
identity load-order-independently as `ResolvedFormID` = (plugin file name,
objectID); `FormIDResolver(pluginName:masters:)` maps raw file-local IDs to
it. Plugin-name matching is currently verbatim-case (vanilla masters are
spelled consistently); case-insensitive matching may be needed for mods.

ESL note: the 0xFE prefix space is a runtime load-order construct — raw
FormIDs inside a plugin file never use it. ESL-flagged plugins still encode
master indices as above; only the runtime slotting differs. Not needed until
plugin load order lands.

## Verification

Unit tests: `openskyTests/PluginHeaderTests.swift` (synthetic fixtures).
Runtime probe 2026-07-09 against all five vanilla masters: HEDR version 1.71,
esm+localized flags set everywhere; masters Update.esm -> [Skyrim.esm],
Dawnguard/HearthFires/Dragonborn -> [Skyrim.esm, Update.esm]; sample records
resolve to the defining plugin; deep walk shows max master index used ==
masters.count exactly (Update.esm 1/1, Dawnguard.esm 2/2) — no out-of-range
indices in vanilla data.
