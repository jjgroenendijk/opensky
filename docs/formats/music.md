---
type: File Format
title: Music records (MUSC, MUST)
description: Skyrim SE MUSC music-type and MUST music-track record fields, the
  CELL/WRLD/REGN links that select them, and OpenSky's decode + path policy.
tags: [format, plugin, audio, music]
timestamp: 2026-07-26T00:00:00Z
---

# Music records (MUSC, MUST)

Skyrim SE splits music into two records. A `MUSC` music type is a playlist: it
names the `MUST` tracks it may choose from and carries the policy the runtime
applies when switching to it (priority, ducking, fade duration, cycling rules).
A `MUST` music track is one entry in that playlist: an audio file plus its
loop points, an optional finale file, and cue points.

The world tells the runtime which `MUSC` applies through three links, in
increasing generality: `CELL.XCMO`, then the region's `REGN.RDMO`, then the
worldspace default `WRLD.ZNAM`.

## Sources

Every field below is taken from one of:

* UESP [`MUSC`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MUSC)
* UESP [`MUST`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MUST)
* UESP [`CELL`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL),
  [`WRLD`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WRLD),
  [`REGN`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REGN)
* xEdit `dev-4.1.6`
  [`Core/wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
  — `MUSC` at lines 7074-7092, `MUST` at lines 7203-7226, `CELL.XCMO` at line
  4378, `WRLD.ZNAM` at line 10772, `REGN.RDMO` at line 9984.

Both sources agree on every field OpenSky decodes. Where only one names
something, the table says so.

## MUSC — music type

Decoder: `MusicType` in `opensky/Formats/ESM/Records/MusicRecords.swift`.

| field | on-disk type | decoded value | source |
| --- | --- | --- | --- |
| `EDID` | zstring | optional editor ID | both |
| `FNAM` | uint32 | flags bitfield, see below | both |
| `PNAM` | 4-byte struct | uint16 priority, uint16 ducking | both |
| `WNAM` | float | fade duration in seconds | both |
| `TNAM` | FormID array | ordered `MUST` links, arbitrary count | both |

`PNAM` priority runs the opposite way to intuition: 1 is the highest priority
and 100 the lowest (UESP). The ducking uint16 is stored scaled by 100, so 126
means 1.26 dB; the authored maximum is 10000 (100.00 dB). `MusicType` divides
by 100 and exposes `duckingDecibels`.

`FNAM` flag bits:

| bit | name | note |
| --- | --- | --- |
| `0x01` | plays one selection | |
| `0x02` | abrupt transition | |
| `0x04` | cycle tracks | |
| `0x08` | maintain track order | only valid together with cycle tracks |
| `0x10` | — | unnamed in both sources; kept in `rawValue`, no Swift name |
| `0x20` | ducks current track | |
| `0x40` | doesn't queue | named only by xEdit, and only for SSE |

## MUST — music track

Decoder: `MusicTrack` in the same file.

| field | on-disk type | decoded value | source |
| --- | --- | --- | --- |
| `EDID` | zstring | optional editor ID | both |
| `CNAM` | uint32 | track type tag, see below | both |
| `FLTV` | float | duration in seconds | both |
| `DNAM` | float | fade-out in seconds | both |
| `ANAM` | zstring | track filename | both |
| `BNAM` | zstring | finale filename | xEdit names it "Finale FileName"; UESP calls it "b track" |
| `FNAM` | float array | cue points in seconds | both |
| `LNAM` | 12-byte struct | float loop begin, float loop end, uint32 loop count | both |
| `SNAM` | FormID array | child `MUST` links (palette tracks) | both |
| `CITC` | uint32 | condition count — not decoded | both |
| `CTDA` | condition | conditions — not decoded | both |

`CNAM` is a hashed tag rather than a dense enumeration, so `MusicTrack.TrackType`
carries an `unknown(UInt32)` case:

| value | meaning |
| --- | --- |
| `0x6ED7E048` | single track |
| `0xA1A9C4D5` | silent track |
| `0x23F678C3` | palette |

`FLTV` is authored on silent and palette tracks; `DNAM` appears on palette
tracks (UESP). OpenSky does not enforce that pairing — a track that carries an
unexpected combination decodes with whatever it holds, and the caller decides.

Palette records predate `MUSC` and behave like a nested playlist: they carry
`SNAM` instead of `ANAM`, and a null FormID inside `SNAM` is a layer separator
rather than a broken link (UESP MUST). `MusicTrack.tracks` therefore keeps null
entries verbatim; the same is true of `MusicType.tracks` so callers see the
authored ordering. `MusicRecordStore.resolve(musicType:)` is what drops them.

## World links

| record | field | on-disk type | decoded property |
| --- | --- | --- | --- |
| `CELL` | `XCMO` | FormID -> `MUSC` | `Cell.musicType` |
| `WRLD` | `ZNAM` | FormID -> `MUSC` | `Worldspace.musicType` |
| `REGN` | `RDMO` | FormID -> `MUSC` | `Region.musicType` |

`REGN.RDMO` sits in the region's area-field stream, but UESP notes it "can
appear with RDSA under same RDAT or on its own". OpenSky therefore accepts it
regardless of the current `RDAT` area type, unlike `RDWT` and `RDSA`, which are
bound to their type-3 and type-7 areas. All three links fold an authored null
FormID to `nil`, meaning "no override" rather than "form 0".

## Decode policy

The music decoders follow the policy already pinned by
[sound records](/formats/sound.md) and
[acoustic space](/formats/acoustic-space.md):

* The record FourCC is verified; a mismatch throws `ESMError.malformed`.
* Fixed-width fields decode only at their documented width. A wrong-width
  payload is ignored, never partially read — a short read would shift every
  following field.
* Array fields (`TNAM`, `SNAM`, `FNAM`) require a payload that is a non-zero
  multiple of the element size; anything else decodes to an empty array.
* Unknown fields are skipped. Malformed input never crashes the engine.

## Path resolution

`MusicRecordStore.canonicalMusicPath(_:)` turns an authored `ANAM`/`BNAM`
filename into a VFS key. Music assets live under `music\...`, not the
`sound\...` root that `SoundRecordStore` applies to `SNDR` tracks, so the two
normalizers are deliberately separate.

The rules, in order: reject absolute paths (a leading `/` or `\`) and any path
that still carries a `:` after normalization; strip a leading `data\` when the
remainder is already music-rooted; otherwise prefix `music\` when the path is
not already music-rooted. A filename that fails the rules is dropped without
reordering the survivors.

## Not decoded yet

* `MUST` `CITC` + `CTDA` conditions. OpenSky has no condition evaluator, so a
  conditional track is treated as unconditional. Revisit when the condition
  system lands.
* `MUSC`/`MUST` have no other Skyrim SE fields; modder-added fields stream past
  untouched.
* The `LCTN.NAM1` location music link (xEdit `wbDefinitionsTES5.pas`:6506) is
  real but out of scope: OpenSky does not decode `LCTN` at all yet.

## See also

* [Sound records](/formats/sound.md) — the SNDR/SOUN sibling and the
  `sound\...` path rules this page contrasts with.
* [Weather records](/formats/weather.md) — the REGN area-field stream `RDMO`
  lives in.
* [Record decoders](/formats/records.md) — the CELL and WRLD decoders extended
  with `XCMO` and `ZNAM`.
