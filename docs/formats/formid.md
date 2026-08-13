---
type: File Format
title: FormID and TES4 plugin header
description: TES4 header layout, master lists, and how raw FormIDs resolve to (plugin, objectID).
tags: [format, plugin, esm, formid, records]
timestamp: 2026-08-13T00:00:00Z
---

# FormID + TES4 plugin header, Skyrim SE

## Contents

* TES4 record fields
* FormID layout
* Cross-plugin record index
* Verification

Every record carries a 32-bit FormID (offset 0x0C of the record header, see
[ESM container](/formats/esm.md)). Raw FormIDs are file-relative: their top
byte only means something together with the owning plugin's master list from
its TES4 header. This page covers both.

References: UESP "Skyrim Mod:Mod File Format" — TES4 record
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>), UESP "Skyrim Mod:FormIDs"
(<https://en.uesp.net/wiki/Skyrim_Mod:FormIDs>).
Impl: `opensky/Engine/Formats/ESM/PluginHeader.swift`, `FormID.swift`, and
`opensky/Engine/GameData/RecordIndex.swift`.

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
fields. Strings are zstrings under the engine-wide lenient text policy
([string decoding](/decisions/string-decoding.md)). Missing HEDR ->
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
it. Plugin-name matching in `FormIDResolver` itself is verbatim-case (vanilla
masters are spelled consistently); the session-stable `ReferenceKey` built on
top of `ResolvedFormID` lowercases the plugin name instead, since neither raw
`FormID` nor `ResolvedFormID` is safe as a persistent identity across a
session — see [Runtime reference identity](/engine/runtime-state.md).

ESL note: the 0xFE prefix space is a runtime load-order construct — raw
FormIDs inside a plugin file never use it. ESL-flagged plugins still encode
master indices as above; only the runtime slotting differs. The
[plugin load order](/formats/plugins-txt.md) now places light plugins in the
right sequence, but the 0xFE slotting itself is still undecoded, so the Load
Order panel shows a plain position rather than a runtime index.

## Cross-plugin record index

`RecordIndex` visits the active plugins from low to high priority and walks all
requested top groups together. It resolves each record's file-relative FormID
through that plugin's TES4 master list and keys the winner by `ResolvedFormID`.
Active plugin names supply canonical filesystem spelling, matched
case-insensitively against MAST entries. A later valid record replaces an
earlier definition; deleted records, malformed field framing, unreadable groups,
and unreadable plugins do not erase the last valid record.

The index retains opaque `ESMRecord` candidates and does not interpret
type-specific bodies. Its decode seam tries candidates from high to low
priority, so a malformed override falls back to the last decodable definition.
The result distinguishes an undecodable identity from a missing one;
`RecordIndexResolution` separately distinguishes null references and unknown
source plugins. The eight M18 families built over the five masters in 135 ms on
2026-08-13, collecting 4,093 record headers in one pass before override
identities were collapsed.

## Verification

Unit tests: `openskyTests/PluginHeaderTests.swift` and `RecordIndexTests.swift`
(synthetic fixtures).
Runtime probe 2026-07-09 against all five vanilla masters: HEDR version 1.71,
esm+localized flags set everywhere; masters Update.esm -> [Skyrim.esm],
Dawnguard/HearthFires/Dragonborn -> [Skyrim.esm, Update.esm]; sample records
resolve to the defining plugin; deep walk shows max master index used ==
masters.count exactly (Update.esm 1/1, Dawnguard.esm 2/2) — no out-of-range
indices in vanilla data.

`RecordIndexRealDataTests` pins the eight-family collection floors and
`Skyrim.esm:013794` (`ActorTypeNPC`) against the user's active load order.
