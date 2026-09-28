---
type: File Format
title: FaceFX lip animation (.lip)
description: Skyrim SE .lip header shapes, the slot stride in the duration field, the ambiguous
  marker bytes and how the decoder resolves them, and the slot-to-TRI mapping.
tags: [format, audio, voice, dialogue, facefx, animation]
---

# FaceFX lip animation (.lip)

A voice file (see [FUZ](/formats/fuz.md)) can carry a `.lip` blob next to its audio. The blob
is a FaceFX animation: a header of at least 24 bytes, then a sparse stream of values on a
30 Hz grid of slots. OpenSky decodes the grid and maps speech slots to the named morph targets
of the actor's [FaceGen TRI](/formats/tri.md).

## Sources and confidence

The byte model comes from the clean-room
[OpenFaceFX research codec](https://github.com/OpenFaceFX/OpenFaceFX/blob/main/tools/lip_codec_research.py).
It was then checked against every `.lip` blob in the vanilla voice archive.

| Claim | Confidence | Evidence |
| --- | --- | --- |
| 24-byte little-endian header, field sizes | confirmed | Public codec and vanilla sweep |
| Version `1` | confirmed | Vanilla sweep |
| `durationTicks == 4 * slotsPerFrame * frameCount + 28` | confirmed | Vanilla sweep, both header shapes |
| Stride 33 goes with vocabulary 16, stride 8 with vocabulary 8 | confirmed | Vanilla sweep |
| A second header shape has 1 or 3 extra bytes before the tuple width | confirmed | Vanilla sweep |
| Token, duplicate, and suffix marker framing | confirmed | Byte-exact public round trips and vanilla sweep |
| Marker tag / 4 is a slot skip | confirmed for multiples of 4 | Public grid rebuild and vanilla sweep |
| Slots are frame-major, sampled at 30 Hz | confirmed | Public grid rebuild |
| A duplicate value is an equal tangent | inferred | Public codec. OpenSky counts it and uses the first value |
| Tuple width 3 versus 2 changes decoding | unknown | Both decode the same. OpenSky records the value |
| Meaning of header offset `0x16` | unknown | It varies. OpenSky keeps and counts it |
| Low two bits of a marker tag | unknown | About 1% of tags are not multiples of 4 |
| Even slots map to the TRI targets in the table below | inferred | 16 targets, paired slot layout, visual A/B tests |

The payload holds no phoneme name, viseme ID, or TRI target name. The slot table is an
inference, not an on-disk enum.

About 96% of vanilla lip blobs decode. The rest fail with a typed error, and their audio
still plays. Most failures have no header tail that can be found: the field at `0x0e` reads
`7`, and the vocabulary field explains no stride. A few have a token stream with no framing
that spans the payload.

## Header

| Offset | Type | Field | Check |
| --- | --- | --- | --- |
| `0x00` | uint32 | Version | Must be 1 |
| `0x04` | uint32 | Duration ticks | Gives the slot stride, below |
| `0x08` | uint32 | Active curve count | Recorded, not checked |
| `0x0c` | uint16 | Frame count | Not 0 |
| `0x0e + n` | uint16 | Tuple width | 1 to 3. 3 for humans, 2 in the second shape |
| `0x10 + n` | int32 | First frame | From `-frameCount` to 0 |
| `0x14 + n` | uint16 | Target vocabulary | Must explain the stride |
| `0x16 + n` | uint16 | Unknown | Kept and counted |

`n` is 0 for most files, and 1 or 3 for the second shape. The payload starts at `24 + n`.

Frame 0 is the start of the audio. A negative first frame is preroll. So the sample row for
audio time `t` is `t * 30 - firstFrame`. The duration without preroll is
`(firstFrame + frameCount) / 30` seconds.

## The slot stride is in the duration field

The number of slots per frame is not always 33. The duration field gives it:

```text
durationTicks = 4 * slotsPerFrame * frameCount + 28
```

There are 4 ticks per slot. So 132 ticks per frame means 33 slots (4 x 33). Creature blobs
with vocabulary 8 use 32 ticks per frame, which is 8 slots: one per target. The human files
use two slots per target plus one extra slot.

The vocabulary must agree with the stride: the stride is `targetCount * 2 + 1` or
`targetCount`. This check is what makes the header search below reliable.

## The second header shape

Some blobs have 1 or 3 extra bytes between the frame count and the tuple width. Their tuple
width is 2, not 3. Read at the normal offsets, they give nonsense: tuple widths of 512, 256,
or 1536, and vocabularies in the tens of thousands. Read at the shifted offset, they are a
normal header.

What the extra bytes mean is unknown. The decoder tries offsets `0x0e` to `0x16`. It takes
the first place where the tuple width, the first frame, and the vocabulary all agree with the
stride. It records where it found them. It does not claim the skipped bytes are padding.

## Payload

Each token starts with one float32 value. If the next four bytes are the same, they are a
duplicate and belong to the token. Then an optional three-byte marker can follow, shaped
`00 <tag> 00` with a tag that is not 0. The position moves like this:

```text
frame = position / slotsPerFrame
slot  = position % slotsPerFrame
position += (duplicate ? 2 : 1) + tag / 4
```

To sample a slot, OpenSky interpolates its stored values linearly and clamps the result to
0...1. So negative tangent-like values and the tiny "rest" value cannot push a face outside
its legal morph range.

## Marker bytes are ambiguous

The bytes `00 <tag> 00` do not say what they are. They can also be the start of the next
float32. Example: the weight `0.1250153` is `00 04 00 3E` on disk. So "always read the
marker" and "never read it" are both wrong, and the vanilla data shows it both ways:

- Reading a marker only when `tag % 4 == 0` gets out of step on some blobs. It then reports a
  "non-finite value". The real value starts one byte later. Going back three bytes and reading
  again carries the rest of the stream cleanly to the end.
- Reading a marker for every tag breaks blobs that decode with the first rule, and makes others
  run past their slot count.

So the tag alone cannot decide. The decoder treats each possible marker as a choice and
backtracks. A reading is accepted only if it reaches exactly the end of the payload, with no
non-finite value, and without passing `frameCount * slotsPerFrame`. Tags that are multiples
of 4 are tried as markers first. Other tags are tried as data first. Dead ends are remembered
by byte offset, so the search stays linear. A step limit protects against hostile files.

One result: more than one framing can span a payload. So a blob that lost a few bytes may
decode as a shorter track instead of failing. The bytes cannot tell these cases apart. The
decoder does promise that every key is inside the declared grid, and that it never reads past
the blob.

The active curve count has the same problem. Some creature blobs declare nine curves for a
vocabulary of eight. Nothing uses the field, so it is only recorded.

About 99% of marker tags are multiples of 4. The meaning of the low two bits of the others is
unknown. It could be a time inside a slot or a flag. The skip stays `tag / 4`.

## Slot to TRI target

This mapping is a separate layer, and it covers only the 33-slot human grid. Slots not in the
table are counted, and playback shows active unmapped slots in the Dialogue & Voice readout.
The 8-slot creature grid decodes, but gets no human target names, because there is no
evidence for them.

| Slot | TRI target | Slot | TRI target |
| --- | --- | --- | --- |
| 0 | `Aah` | 16 | `i` |
| 2 | `BigAah` | 18 | `k` |
| 4 | `BMP` | 20 | `N` |
| 6 | `ChjSh` | 22 | `Oh` |
| 8 | `DST` | 24 | `OohQ` |
| 10 | `Eee` | 26 | `R` |
| 12 | `Eh` | 28 | `Th` |
| 14 | `FV` | 30 | `W` |

`World > Dialogue & Voice` shows the header shape and stride of the current line.
