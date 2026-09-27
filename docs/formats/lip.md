---
type: File Format
title: FaceFX lip animation (.lip)
description: Skyrim SE .lip headers, the slot stride in the duration field, the ambiguous
  marker bytes and how OpenSky resolves them, and the speech slot mapping.
tags: [format, audio, voice, dialogue, facefx, animation]
---

# FaceFX lip animation (.lip)

A voice file (`.fuz`, see [FUZ](/formats/fuz.md)) may hold a `.lip` block next to the
audio. It is a FaceFX animation: a header of at least 24 bytes, then a sparse list of
values on a grid. The grid has 30 frames per second, and each frame has a fixed number of
slots. OpenSky maps the speech slots to the named [FaceGen TRI targets](/formats/tri.md) of
the actor's face.

## Sources and confidence

The byte model comes from the clean-room
[OpenFaceFX research codec](https://github.com/OpenFaceFX/OpenFaceFX/blob/main/tools/lip_codec_research.py).
It was then checked against every vanilla voice file.

| Claim | Confidence | Evidence |
| --- | --- | --- |
| 24-byte little-endian header and its field sizes | confirmed | Public codec, vanilla files |
| Version `1` | confirmed | Vanilla files |
| `durationTicks == 4 * slotsPerFrame * frameCount + 28` | confirmed | Vanilla files, both header families |
| Stride 33 goes with vocabulary 16; stride 8 with vocabulary 8 | confirmed | Vanilla files |
| A second header family has 1 or 3 extra bytes before the tuple width | confirmed | Vanilla files |
| Value, duplicate, and marker framing | confirmed | Exact public round trips, vanilla files |
| Marker tag / 4 is a slot skip | confirmed for multiples of 4 | Public grid rebuild, vanilla files |
| Slots are frame by frame, 30 frames per second | confirmed | Public grid rebuild |
| A duplicate value means equal tangents | inferred | Public codec. OpenSky uses the first value |
| Tuple width 3 or 2 changes anything | unknown | Both decode the same. OpenSky keeps the value |
| Meaning of header offset `0x16` | unknown | It varies. OpenSky keeps it |
| Meaning of the low two bits of a marker tag | unknown | 1% of tags are not multiples of 4 |
| Even slots map to the TRI targets in the table below | inferred | 16 targets, the paired grid shape, visual comparison |

The file stores no phoneme names and no TRI target names. So the slot table is OpenSky's
inference, not a field on disk.

Of the 74,070 vanilla voice files with lip data, 70,939 decode. About 3,100 have no header
tail OpenSky can find: the field at `0x0e` reads `7`, and no vocabulary value explains the
stride. 27 more have a value list that no reading fits. These return an error, and the
audio still plays.

## Header

| Offset | Type | Name | Check |
| --- | --- | --- | --- |
| `0x00` | uint32 | Version | Must be `1` |
| `0x04` | uint32 | Duration ticks | Gives the slot stride, below |
| `0x08` | uint32 | Active curve count | Kept, not checked |
| `0x0c` | uint16 | Frame count | Not 0 |
| `0x0e + n` | uint16 | Tuple width | 1 to 3. 3 for humans, 2 in the second family |
| `0x10 + n` | int32 | First frame | `-frameCount` to 0 |
| `0x14 + n` | uint16 | Target vocabulary | Must explain the stride |
| `0x16 + n` | uint16 | Unknown | Kept |

`n` is 0 for most files, and 1 or 3 for the second family. The values start at `24 + n`.

Frame 0 is the start of the audio. A negative first frame means frames before the audio
starts. So the grid row for audio time `t` is `t * 30 - firstFrame`. The duration is
`(firstFrame + frameCount) / 30` seconds.

The active curve count does not always match. 952 creature files say 9 curves with a
vocabulary of 8. Nothing uses the field, so OpenSky does not check it.

## The slot stride is in the duration

The number of slots per frame is not always 33. The duration field gives it:

```text
durationTicks = 4 * slotsPerFrame * frameCount + 28
```

A slot is 4 ticks, so the common 132 ticks per frame is `4 * 33`. Files with vocabulary 8
use 32 ticks per frame, which is `4 * 8`. That is one slot per target. The human files use
two slots per target plus one extra slot.

The vocabulary field must agree with the stride: `targetCount * 2 + 1` or `targetCount`.

## The second header family

About 5,000 files have the normal fields at a moved offset. There are 1 or 3 extra bytes
between the frame count and the tuple width, and the tuple width is 2. Read at the normal
offsets, these files show tuple widths like 512, 256, or 1536, and huge vocabularies. The
meaning of the extra bytes is unknown. So OpenSky tries offsets `0x0e` to `0x16` and takes
the first one where the tuple width, first frame, and vocabulary all agree with the stride.
It does not claim that the skipped bytes are padding.

## Values

Each entry starts with one float32 value. If the next four bytes are the same, the entry
takes that duplicate too. Then an optional three-byte marker may follow: `00 <tag> 00`
with a tag that is not 0. The position moves like this:

```text
frame = position / slotsPerFrame
slot  = position % slotsPerFrame
position += (duplicate ? 2 : 1) + tag / 4
```

Between stored values, OpenSky interpolates linearly. It clamps the result to 0...1. Some
values look like signed tangents, and there is a rest value near 0. The clamp keeps a face
inside its legal morph range.

## The marker bytes are ambiguous

The bytes `00 <tag> 00` can also be the first three bytes of the next float32. For example,
the small weight `0.1250153` is `00 04 00 3E` on disk. So always reading a marker is wrong,
and never reading one is also wrong. The vanilla files show both:

- Accepting only tags that are multiples of 4 gets out of step on about 3,700 files. The
  reader then sees a value that is not finite. The real value is one byte later.
- Accepting every tag that is not 0 breaks about 1,800 files that decode with the first
  rule, and makes about 5,200 more run past the grid.

So the tag alone cannot decide. OpenSky treats each possible marker as a choice and goes
back when a choice fails. A reading is accepted only if it reaches exactly the end of the
data, has only finite values, and stays inside `frameCount * slotsPerFrame`. Tags that are
multiples of 4 are tried as a marker first. Other tags are tried as data first. OpenSky
remembers failed byte offsets, so the search stays linear. A step limit protects against a
hostile file.

Because more than one reading can fit, a `.lip` block that lost a few bytes may decode as a
shorter track instead of failing. The bytes alone cannot show the difference. OpenSky does
promise that every value lies inside the grid the header gives, and that it never reads
past the block.

99% of accepted tags are multiples of 4. The meaning of the low two bits of the others is
unknown. They could be a time inside a slot, or flags. So the skip stays `tag / 4`.

## Speech slots

The table covers only the 33-slot human grid. Slots not in the table are counted, and
`World > Dialogue & Voice` shows active slots that have no mapping. The 8-target creature
files decode but get no human mouth shapes, because there is no evidence for them.

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

`World > Dialogue & Voice` also shows which header family and stride the current line uses.
