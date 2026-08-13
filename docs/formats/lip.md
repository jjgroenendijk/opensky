---
type: File Format
title: FaceFX lip animation (.lip)
description: Skyrim SE .lip header families, the tick-derived slot stride, the ambiguous
  marker framing and how the decoder resolves it, positional speech-slot mapping, and the
  boundary between confirmed bytes and inference.
tags: [format, audio, voice, dialogue, facefx, animation]
timestamp: 2026-08-12T00:00:00Z
---

# FaceFX lip animation (.lip)

Skyrim voice containers carry an optional `.lip` payload beside the encoded audio. It is a
FaceFX animation header of at least 24 bytes followed by a sparse token stream over a 30 Hz
grid of positional slots. `LIPFile` decodes that grid and `LipSyncPlayback` maps its
positional speech slots onto the named [FaceGen TRI targets](/formats/tri.md) already
attached to an actor.

## Contents

- Evidence and confidence
- Header
- The slot stride is in the duration field
- The alternate header family
- Payload and routing
- Marker framing is ambiguous, and the payload decides
- Positional slot mapping
- Verification

## Evidence and confidence

The byte model comes from the clean-room
[OpenFaceFX research codec](https://github.com/OpenFaceFX/OpenFaceFX/blob/main/tools/lip_codec_research.py),
then was checked read-only against the installed vanilla voice archive. No game bytes or
rendered captures are committed.

| Claim | Confidence | Evidence |
| --- | --- | --- |
| 24-byte little-endian header and its field widths | confirmed | Public codec and vanilla sweep |
| version `1` | confirmed | Vanilla sweep |
| `durationTicks == 4 * slotsPerFrame * frameCount + 28` | confirmed | Vanilla sweep, both families |
| slot stride 33 accompanies vocabulary 16, stride 8 accompanies vocabulary 8 | confirmed | Vanilla sweep |
| a second header family carries one or three extra bytes before the tuple width | confirmed | Vanilla sweep |
| payload token, exact duplicate and suffix marker framing | confirmed | Byte-exact public round trips and vanilla sweep |
| marker tag divided by four is a positional skip | confirmed for multiples of four | Public grid reconstruction and vanilla sweep |
| frame-major slots sampled at 30 Hz | confirmed | Public grid reconstruction |
| duplicate is an equal-tangent representation | inferred | Public codec; OpenSky tallies it and samples the first value |
| tuple width `3` versus `2` distinguishes anything the decoder must act on | unknown | Both decode identically; OpenSky records the value |
| header offset `0x16` semantic | unknown | It varies; OpenSky preserves and tallies the value |
| the low two bits of a marker tag | unknown | 1% of tags are not multiples of four |
| even slots map to TRI speech targets in the table below | inferred | 16 targets, paired-slot grid shape and visual A/B evidence |

The last distinction matters: the payload stores no phoneme name, viseme ID or TRI target
string. OpenSky does not describe the inferred table as an on-disk enum.

The 2026-08-12 vanilla sweep covered all 75,408 `.fuz` entries. 74,070 carry lip data and
70,939 of those decode; the 2026-08-11 decoder managed 61,484 of the same blobs. The three
findings below are what closed that gap, each measured across the whole corpus rather than
inferred from a coincidental offset. The decoded set is 65,138 blobs at the plain
24-byte header, 4,749 at 25 bytes and 100 at 27, plus 729, 221 and 2 of the 8-target creature
family at the same three header sizes. What still declines to decode is 3,104 blobs with no
locatable header tail — a shape whose field at `0x0e` reads `7` and whose vocabulary field
explains no stride — and 27 whose token stream frames to no reading that spans the payload.
Both return typed `LIPError` results, and normal audio still plays for them.

## Header

| Offset | Type | OpenSky name | Validation |
| --- | --- | --- | --- |
| `0x00` | `uint32` | version | must be `1` |
| `0x04` | `uint32` | duration ticks | fixes the slot stride, below |
| `0x08` | `uint32` | active curve count | recorded, not validated |
| `0x0c` | `uint16` | frame count | non-zero |
| `0x0e + n` | `uint16` | tuple width | `1 ... 3`; `3` humanoid, `2` in the alternate family |
| `0x10 + n` | `int32` | first frame | `-frameCount ... 0` |
| `0x14 + n` | `uint16` | target vocabulary | must explain the stride |
| `0x16 + n` | `uint16` | unknown value | retained and tallied |

`n` is 0 for most of the corpus and 1 or 3 for the alternate family; `LIPHeader.headerSize`
records `24 + n`, which is where the payload starts.

Frame zero is the audio start. A negative first frame is preroll, so the sample row for audio
time `t` is `t * 30 - firstFrame`. The exposed duration excludes that preroll:
`(firstFrame + frameCount) / 30` seconds.

## The slot stride is in the duration field

Slots per frame is not the constant 33 the first implementation assumed. The duration field
carries it:

```text
durationTicks = 4 * slotsPerFrame * frameCount + 28
```

Four ticks per slot, so the familiar `132` ticks per frame is `4 * 33`. The 729 blobs whose
vocabulary is 8 use `32` ticks per frame, which is `4 * 8`: eight slots per frame, one per
target rather than the humanoid family's two per target plus a trailing slot. Reading the
stride out of the duration rather than assuming it is also what turns the old
"duration ticks N, expected M" rejection into a decode.

The vocabulary field then has to agree with that stride — `targetCount * 2 + 1` or
`targetCount` — which is what makes the header-tail search below a match rather than a
coincidence.

## The alternate header family

4,972 blobs carry the standard fields at a shifted offset: one extra byte (4,749 blobs, of
which 221 are the 8-target creature family) or three (102) sit between the frame count and
the tuple width. Their tuple width is `2` rather than `3`. Read at the fixed offsets those
bytes produce the apparent tuple widths `512`, `256` and `1536` and vocabularies in the tens
of thousands that the M17 acceptance gate walked past; read at the shifted offset they are an
ordinary header. What the extra bytes mean is unknown, so `LIPDecoder` searches offsets
`0x0e` through `0x16` for the first tuple width, pre-roll and vocabulary that are jointly
consistent with the stride, and records where it found them. It does not claim the bytes it
skipped are padding.

## Payload and routing

Each token begins with one Float32 value. If the next four bytes are identical, the token
consumes that duplicate too. An optional three-byte suffix follows when it has the shape
`00 <tag> 00` with a non-zero tag. Walking a flattened position:

```text
frame = position / slotsPerFrame
slot  = position % slotsPerFrame
position += (duplicate ? 2 : 1) + tag / 4
```

Sampling linearly interpolates the stored values for each slot and clamps the result to zero
through one. Signed tangent-looking values and the near-zero rest sentinel therefore cannot
push a face outside its legal morph range.

## Marker framing is ambiguous, and the payload decides

A `00 <tag> 00` triple is not self-identifying. The same three bytes are a legal prefix of the
next Float32 — a small positive weight such as `0.1250153` is `00 04 00 3E` on disk — so a
decoder that always consumes the triple and a decoder that never does are both wrong, and the
corpus proves it both ways:

- Requiring `tag % 4 == 0` (the pre-2026-08-12 rule) loses byte phase on 3,683 blobs. The
  symptom was the `non-finite curve value at byte N` rejection: at the failure the real value
  sits one byte later, and re-walking three bytes earlier carries the rest of the stream to
  the end of the blob cleanly. The bytes are not non-finite; the reader was out of phase.
- Accepting every non-zero tag instead breaks 1,828 blobs that decoded under the old rule and
  pushes 5,203 more past their own slot budget.

So the tag value cannot decide it alone. `LIPDecoder` treats each triple as a choice point
and backtracks: a reading is accepted only if it carries the token stream to exactly the end
of the payload without a non-finite value and without overrunning
`frameCount * slotsPerFrame`. Multiples of four are tried as a suffix first and everything
else as data first, so every blob that decoded before decodes identically. Dead ends are
remembered by byte offset, which keeps the search linear; across the corpus no blob needed
more than a couple of steps per key, and a step budget bounds a hostile file.

One consequence is worth stating plainly: because more than one framing can span a payload,
a `.lip` blob that has lost a few bytes may decode as a shorter track instead of failing. The
decoder cannot tell those apart from the bytes alone. What it does guarantee is that every key
it emits sits inside the grid the header declares and that it never reads past the blob.

The active curve count is in the same position. 952 creature blobs declare nine curves against
a vocabulary of eight; nothing indexes by the field, so it is recorded rather than validated.

99% of accepted tags are multiples of four. What the low two bits of the rest mean is
unknown — a sub-slot key time and a flag field are both consistent with what is on disk — so
the skip stays `tag / 4` and the question stays open rather than being answered by assertion.

## Positional slot mapping

The current mapping is deliberately a separate `LipVisemeMapping` layer, and it describes the
33-slot humanoid grid only. Slots absent from the table are not discarded silently: the parser
tallies their keys and playback reports any active unmapped slots through `LipSyncStatsLabel`.
The 8-target creature family therefore decodes and reports its slots without being given
human viseme names it has no evidence for.

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

Synthetic fixtures cover header validation, truncation, duplicate and marker routing, preroll,
interpolation, clamping, the mapping table, the shifted header, the tick-derived stride, and a
payload whose only framing that spans the blob is the one the greedy reading rejects.
`LipSyncRealDataTests` walks every embedded payload in the vanilla `.fuz` corpus, proves every
blob is either decoded or returns a typed failure, verifies decoded samples stay finite, tallies
the header layouts, and writes derived counts only to `logs/lip-sweep/<stamp>/`.
`LipSyncRenderRealDataTests` samples one real track at three fixed times with lip sync off and
on, requires a pixel difference for every pair and requires an exact repeat for the same inputs.
Its local PNGs remain in the test run under `logs/`.
`World > Dialogue & Voice` shows the decoded layout of the active line in `LipSyncStatsLabel`,
so which header family and stride a line used is visible without a CLI command.
