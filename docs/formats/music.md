---
type: File Format
title: Music records (MUSC, MUST)
description: Skyrim SE MUSC music type and MUST music track fields, the CELL, WRLD, and REGN
  links that pick them, and music file paths.
tags: [format, plugin, audio, music]
---

# Music records (MUSC, MUST)

Skyrim SE describes music with two records:

- `MUSC`, a music type, is a playlist. It lists `MUST` tracks and says how to switch to it:
  priority, ducking, fade time, and cycling.
- `MUST`, a music track, is one entry. It has a sound file, loop points, an optional finale
  file, and cue points.

The world picks a `MUSC` through three links. The most specific link wins: `CELL XCMO`,
then the region's `REGN RDMO`, then the worldspace default `WRLD ZNAM`. See
[music runtime](/engine/music.md).

## Sources

- UESP [`MUSC`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MUSC),
  [`MUST`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MUST),
  [`CELL`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL),
  [`WRLD`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WRLD), and
  [`REGN`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REGN).
- xEdit `dev-4.1.6`
  [`Core/wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas):
  `MUSC` lines 7074-7092, `MUST` lines 7203-7226, `CELL XCMO` line 4378, `WRLD ZNAM` line
  10772, `REGN RDMO` line 9984.

Both sources agree on every field below, unless the table says otherwise.

## MUSC

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FNAM` | uint32 | Flags, below |
| `PNAM` | 4 bytes | uint16 priority, uint16 ducking |
| `WNAM` | float32 | Fade time in seconds |
| `TNAM` | FormID list | `MUST` tracks, in order |

Priority 1 is the highest and 100 the lowest (UESP). Ducking is stored times 100, so 126
means 1.26 dB. The highest value the editor allows is 10000 (100.00 dB).

| Flag | Meaning |
| --- | --- |
| `0x01` | Plays one selection |
| `0x02` | Abrupt transition |
| `0x04` | Cycle tracks |
| `0x08` | Maintain track order. Only valid with cycle tracks |
| `0x10` | No name in either source. Kept as a raw bit |
| `0x20` | Ducks current track |
| `0x40` | Doesn't queue. Named only by xEdit, and only for Skyrim SE |

## MUST

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `CNAM` | uint32 | Track type, below |
| `FLTV` | float32 | Duration in seconds |
| `DNAM` | float32 | Fade out in seconds |
| `ANAM` | zstring | Track file name |
| `BNAM` | zstring | Finale file name. UESP calls it "b track" |
| `FNAM` | float32 list | Cue points in seconds |
| `LNAM` | 12 bytes | float32 loop begin, float32 loop end, uint32 loop count |
| `SNAM` | FormID list | Child `MUST` tracks (palette tracks) |
| `CITC` | uint32 | Condition count. See [conditions](/formats/conditions.md) |
| `CTDA` | condition | Conditions |

`CNAM` is a hash, not a small number:

| Value | Meaning |
| --- | --- |
| `0x6ED7E048` | Single track |
| `0xA1A9C4D5` | Silent track |
| `0x23F678C3` | Palette |

UESP says silent and palette tracks have `FLTV`, and palette tracks have `DNAM`. OpenSky
does not enforce this.

A palette is older than `MUSC` and works like a playlist inside a track. It has `SNAM`
instead of `ANAM`. A null FormID in `SNAM` separates layers. It is not a broken link (UESP
MUST). So OpenSky keeps null entries in `SNAM` and `TNAM` when it reads them, and drops
them only when it builds the playlist.

## World links

| Record | Field | Type |
| --- | --- | --- |
| `CELL` | `XCMO` | FormID of a `MUSC` |
| `WRLD` | `ZNAM` | FormID of a `MUSC` |
| `REGN` | `RDMO` | FormID of a `MUSC` |

UESP says `RDMO` "can appear with RDSA under same RDAT or on its own". So OpenSky reads it
in any region area. See [weather records](/formats/weather.md) for region areas. A null
FormID in any of the three links means "no music set here".

## Field sizes

- Fixed-size fields are read only at their documented size. A field of another size is
  ignored, because a short read would move every later field.
- List fields (`TNAM`, `SNAM`, `FNAM`) must be a multiple of the element size and not
  empty. Otherwise they give an empty list.

## Path resolution

Music files live under `music\...`, not under `sound\...` like sound effects. So music paths
have their own rules. In order:

1. Remove a leading `/` or `\`.
2. Drop a path that still has a `:`, because it names a drive.
3. Remove a leading `data\` when the rest starts with `music\`.
4. Otherwise add `music\` in front if it is missing.

A dropped path does not change the order of the others.

The leading separator must be removed, not rejected. Most vanilla tracks are written as
`\Data\Music\...`. This is a Windows "from the root" marker, not a drive. In `Skyrim.esm`,
209 of the 242 different `ANAM` and `BNAM` names look like this. The VFS already rejects `.`
and `..`, so the path cannot leave the data root.

The name in the record is often not the name of the file that ships. See
[shipped-file resolution](/engine/music.md#finding-the-shipped-file).

## Not used yet

- `MUST` conditions are read but not evaluated. A track with conditions plays as if it had
  none.
- `LCTN NAM1`, the music of a location (xEdit `wbDefinitionsTES5.pas` line 6506), is read by
  the [location](/formats/locations.md) decoder but does not pick music yet.
