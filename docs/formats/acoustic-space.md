---
type: File Format
title: Acoustic space (ASPC)
description: Skyrim SE ASPC record fields, interior-ambience bridge, and the RDAT
  collision with REGN's area header.
tags: [format, plugin, audio, sound]
timestamp: 2026-07-26T00:00:00Z
---

# Acoustic space (ASPC)

OpenSky decodes the `ASPC` acoustic-space record as the interior-ambience bridge
for [world SFX + ambience](/engine/world-sfx.md). An interior CELL points at an
ASPC through `XCAS`; the ASPC supplies a direct ambient `SNDR` and optionally
borrows a REGN's type-7 sound area for richer beds.

The field inventory follows the UESP
[`ASPC`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ASPC) page and xEdit
`dev-4.1.6` [`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
lines 5401-5407.

| field | on-disk type | decoded value |
| --- | --- | --- |
| `EDID` | zstring | optional editor ID |
| `OBND` | object bounds | skipped (no consumer) |
| `SNAM` | FormID | optional direct ambient sound -> `SNDR` |
| `RDAT` | FormID | optional region whose type-7 sound area is borrowed -> `REGN` |
| `BNAM` | FormID | optional reverb environment -> `REVB` (decoded, unused) |

## RDAT collision

`ASPC.RDAT` is a 4-byte FormID into `REGN`. Same FourCC, completely different
layout and target than `REGN.RDAT`, which is an 8-byte area header (see
[weather records](/formats/weather.md)). The two decoders do not share parsing;
each treats RDAT according to its own record's contract.

The CK labels this field `Use Sound from Region (Interiors Only)` — interior
cells have no `XCLR` regions of their own, so to give an interior region-style
ambience the CK lets its ASPC pull a REGN's sound area. The runtime resolves
the borrowed region's `RDSA` entries through the
[weather store](/engine/weather.md) (which already indexes REGN).

## Resolution

`AcousticSpaceStore` (`opensky/Engine/Audio/AcousticSpaceStore.swift`) indexes ASPC
records by FormID at app launch, mirroring the `SoundRecordStore` shape. The
world SFX director's bed resolver (`AmbienceCatalog`) follows the chain
`CELL.XCAS -> ASPC.SNAM` plus `ASPC.RDAT -> REGN` for the borrowed area.

## Defensive policy

The decoder verifies the record FourCC. Unknown fields are skipped. `SNAM`,
`RDAT`, and `BNAM` decode only at their exact documented 4-byte width; a field
with another width is ignored so malformed optional metadata cannot shift reads
or crash the engine. Missing optional fields produce `nil`.

## Verification

`AcousticSpaceRecordTests` covers the complete-record path, the bare-record
fallback, malformed-width rejection, null-FormID handling, and the wrong-record-
type throw. Synthetic ESM fixtures only.
