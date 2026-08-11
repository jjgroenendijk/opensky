---
type: File Format
title: FaceFX lip animation (.lip)
description: Skyrim SE .lip header and sparse 30 Hz curve grid, defensive decode policy,
  positional speech-slot mapping, and the boundary between confirmed bytes and inference.
tags: [format, audio, voice, dialogue, facefx, animation]
timestamp: 2026-08-11T00:00:00Z
---

# FaceFX lip animation (.lip)

Skyrim voice containers carry an optional `.lip` payload beside the encoded audio. It is a
24-byte FaceFX animation header followed by a sparse token stream over a 33-slot, 30 Hz grid.
`LIPFile` decodes that grid and `LipSyncPlayback` maps its positional speech slots onto the
named [FaceGen TRI targets](/formats/tri.md) already attached to an actor.

## Evidence and confidence

The byte model comes from the clean-room
[OpenFaceFX research codec](https://github.com/OpenFaceFX/OpenFaceFX/blob/main/tools/lip_codec_research.py),
then was checked read-only against the installed vanilla voice archive. No game bytes or
rendered captures are committed.

| Claim | Confidence | Evidence |
| --- | --- | --- |
| 24-byte little-endian header and its field widths | confirmed | Public codec and vanilla sweep |
| version `1`, tuple width `3`, vocabulary `16` | confirmed for the standard humanoid family | Vanilla sweep |
| duration ticks equal `132 * frameCount + 28` | confirmed for the standard humanoid family | Public codec and vanilla sweep |
| payload token, exact duplicate and suffix marker framing | confirmed | Byte-exact public round trips and vanilla sweep |
| marker tag divided by four is a positional skip | confirmed | Public grid reconstruction and vanilla sweep |
| 33 positional slots, frame-major, sampled at 30 Hz | confirmed | Public grid reconstruction |
| duplicate is an equal-tangent representation | inferred | Public codec; OpenSky tallies it and samples the first value |
| header offset `0x16` semantic | unknown | It varies; OpenSky preserves and tallies the value |
| even slots map to TRI speech targets in the table below | inferred | 16 targets, paired-slot grid shape and visual A/B evidence |

The last distinction matters: the payload stores no phoneme name, viseme ID or TRI target
string. OpenSky does not describe the inferred table as an on-disk enum.

The archive also contains alternate FaceFX families, especially non-humanoid and expansion
voices, whose apparent tuple widths, vocabularies or payload routing differ. OpenSky reports
those with typed `LIPError.unsupported` or `LIPError.malformed` results instead of guessing a
layout. The corpus gate counts and classifies every such result; normal audio still plays.

The 2026-08-11 vanilla sweep covered all 75,408 `.fuz` entries: 74,070 carried lip data,
61,484 matched the standard family and 12,586 returned typed alternate-layout or malformed
results. The decoded family contained 39,552,280 routed keys, 4,380,391 exact duplicates and
30,190,634 suffix markers. Its unknown header field used 27 distinct values; no sampled
weight was non-finite. The largest alternate-layout tallies were apparent tuple widths 512
(4,975 tracks) and 7 (2,868), vocabulary 8 (729), and non-finite token patterns (2,176).
These are coverage facts, not extra layouts inferred from coincidental offsets.

## Header

| Offset | Type | OpenSky name | Validation |
| --- | --- | --- | --- |
| `0x00` | `uint32` | version | must be `1` |
| `0x04` | `uint32` | duration ticks | must equal `132 * frameCount + 28` |
| `0x08` | `uint32` | active curve count | at most 16 |
| `0x0c` | `uint16` | frame count | non-zero |
| `0x0e` | `uint16` | tuple width | must be `3` |
| `0x10` | `int32` | first frame | `-frameCount ... 0` |
| `0x14` | `uint16` | target vocabulary | must be `16` |
| `0x16` | `uint16` | unknown value | retained and tallied |

Frame zero is the audio start. A negative first frame is preroll, so the sample row for audio
time `t` is `t * 30 - firstFrame`. The exposed duration excludes that preroll:
`(firstFrame + frameCount) / 30` seconds.

## Payload and routing

Each token begins with one Float32 value. If the next four bytes are identical, the token
consumes that duplicate too. An optional three-byte suffix follows when it has the shape
`00 <tag> 00`, with a non-zero tag divisible by four. Walking a flattened position:

```text
frame = position / 33
slot  = position % 33
position += (duplicate ? 2 : 1) + tag / 4
```

The decoder rejects non-finite values, incomplete tokens, frame-grid overruns and trailing
bytes with typed `LIPError.malformed`; supported-layout mismatches use
`LIPError.unsupported`. Sampling linearly interpolates the stored values for each slot and
clamps the result to zero through one. Signed tangent-looking values and the near-zero rest
sentinel therefore cannot push a face outside its legal morph range.

## Positional slot mapping

The current mapping is deliberately a separate `LipVisemeMapping` layer. Slots absent from
the table are not discarded silently: the parser tallies their keys and playback reports any
active unmapped slots through `LipSyncStatsLabel`.

| Slot | TRI target | Slot | TRI target |
| ---: | --- | ---: | --- |
| 0 | `Aah` | 16 | `i` |
| 2 | `BigAah` | 18 | `k` |
| 4 | `BMP` | 20 | `N` |
| 6 | `ChjSh` | 22 | `Oh` |
| 8 | `DST` | 24 | `OohQ` |
| 10 | `Eee` | 26 | `R` |
| 12 | `Eh` | 28 | `Th` |
| 14 | `FV` | 30 | `W` |

## Verification

Synthetic fixtures cover header validation, truncation, duplicate and marker routing,
preroll, interpolation, clamping and the mapping table. `LipSyncRealDataTests` walks every
embedded payload in the vanilla `.fuz` corpus, proves every blob is either decoded or returns
a typed failure, verifies decoded samples stay finite, and writes derived counts only to
`logs/lip-sweep/<stamp>/`. `LipSyncRenderRealDataTests` samples one real track at three fixed
times with lip sync off and on, requires a pixel difference for every pair and requires an
exact repeat for the same inputs. Its local PNGs remain in the test run under `logs/`.
The pinned real line changed 717, 740 and 748 pixels at 0.30, 0.367 and 0.50 seconds.
