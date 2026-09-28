---
type: File Format
title: Music records (MUSC, MUST)
description: MUSC music-type and MUST music-track fields, the CELL, WRLD, and REGN links that
  pick them, and the music path rules.
tags: [format, plugin, audio, music]
---

# Music records (MUSC, MUST)

Skyrim SE describes music with two records:

- `MUSC`, a music type, is a playlist. It lists `MUST` tracks and says how to switch to it:
  priority, ducking, fade time, and cycling.
- `MUST`, a music track, is one playlist entry: a sound file, loop points, an optional
  finale file, and cue points.

The world picks a `MUSC` through three links. The most specific wins: `CELL.XCMO`, then
`REGN.RDMO`, then `WRLD.ZNAM`.

Sources: UESP [`MUSC`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MUSC),
[`MUST`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MUST),
[`CELL`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL),
[`WRLD`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WRLD),
[`REGN`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REGN); xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas):
`MUSC` lines 7074-7092, `MUST` lines 7203-7226, `CELL.XCMO` line 4378, `WRLD.ZNAM` line
10772, `REGN.RDMO` line 9984. Both sources agree on every field below unless the table says
otherwise.

## MUSC music type

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FNAM` | uint32 | Flags, below |
| `PNAM` | 4 bytes | uint16 priority, uint16 ducking |
| `WNAM` | float | Fade time in seconds |
| `TNAM` | FormID list | `MUST` tracks, in order |

Priority 1 is the highest and 100 the lowest (UESP). Ducking is stored times 100: 126 means
1.26 dB. The largest value is 10000, which is 100 dB.

| Flag | Meaning |
| --- | --- |
| `0x01` | Plays one selection |
| `0x02` | Abrupt transition |
| `0x04` | Cycle tracks |
| `0x08` | Maintain track order. Only valid with cycle tracks |
| `0x10` | No name in either source. Kept as a raw bit |
| `0x20` | Ducks current track |
| `0x40` | Doesn't queue. Only xEdit names it, and only for SSE |

## MUST music track

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `CNAM` | uint32 | Track type, below |
| `FLTV` | float | Duration in seconds |
| `DNAM` | float | Fade-out in seconds |
| `ANAM` | zstring | Track file name |
| `BNAM` | zstring | Finale file name. xEdit: "Finale FileName". UESP: "b track" |
| `FNAM` | float list | Cue points in seconds |
| `LNAM` | 12 bytes | float loop begin, float loop end, uint32 loop count |
| `SNAM` | FormID list | Child `MUST` tracks, for palettes |
| `CITC` | uint32 | Condition count (see [conditions](/formats/conditions.md)) |
| `CTDA` | condition | One condition |

`CNAM` is a hash, not a small number:

| Value | Meaning |
| --- | --- |
| `0x6ED7E048` | Single track |
| `0xA1A9C4D5` | Silent track |
| `0x23F678C3` | Palette |

UESP says silent and palette tracks carry `FLTV`, and palettes carry `DNAM`. OpenSky does not
enforce this. It reads whatever a record holds.

A palette is a nested playlist. It has `SNAM` instead of `ANAM`. A null FormID inside `SNAM`
separates layers. It is not a broken link (UESP `MUST`). So the decoded lists keep null
entries. Only the resolve step drops them.

OpenSky reads `MUST` conditions, but the music player does not check them yet. A track with
conditions plays as if it had none.

## World links

| Record | Field | Type |
| --- | --- | --- |
| `CELL` | `XCMO` | FormID of a `MUSC` |
| `WRLD` | `ZNAM` | FormID of a `MUSC` |
| `REGN` | `RDMO` | FormID of a `MUSC` |

`REGN.RDMO` is in the region's area fields. UESP says it "can appear with RDSA under same
RDAT or on its own". So OpenSky accepts it under any `RDAT` area type. This is unlike `RDWT`
and `RDSA`, which belong to area types 3 and 7. A null FormID in any of the three links means
"no override".

`LCTN.NAM1` is a fourth music link, on [locations](/formats/locations.md).

## Bad input

- A wrong record type is an error.
- A fixed-size field is read only at its exact size. A wrong size is ignored, not read in
  part. A short read would shift every later field.
- A list field (`TNAM`, `SNAM`, `FNAM`) must be a non-zero multiple of its element size.
  Otherwise it becomes an empty list.
- Unknown fields are skipped.

## Music paths

Music files live under `music\`, not under `sound\` like sound effects. So music has its own
path rules, applied to `ANAM` and `BNAM` in this order:

1. Remove a leading `/` or `\`.
2. Drop a path that still has a `:`. It names a drive.
3. Remove a leading `data\` when the rest starts with `music\`.
4. Add `music\` when the path does not start with it.

A dropped path does not change the order of the others.

Why step 1 matters: Bethesda writes most music paths as `\Data\Music\...`. On Windows the
leading `\` means "from the root", not a drive. In `Skyrim.esm`, most distinct music file
names look like this. Rejecting them would leave only a small part of the music playable.
The VFS already rejects `.` and `..`, so a path cannot leave the data folder.

The authored name is often not the name of the file that ships. See
[shipped-file resolution](/engine/music.md#finding-the-shipped-file).
