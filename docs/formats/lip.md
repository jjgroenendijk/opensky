---
type: File Format
title: FaceFX lip animation (.lip)
description: Skyrim SE .lip layout - the zero-run compressed body, the dense frame grid,
  the 33 humanoid slots and what each one drives, and how this was confirmed.
tags: [format, audio, voice, dialogue, facefx, animation]
---

# FaceFX lip animation (.lip)

A voice file (`.fuz`, see [FUZ](/formats/fuz.md)) may hold a `.lip` block next to the
audio. Mods also ship it as a loose `.lip` file beside a `.xwm`. It is a FaceFX animation:
a short header, then a compressed grid of float values. The grid has 30 frames per second,
and each frame has one value per slot. On a humanoid head, slots drive the
[FaceGen TRI targets](/formats/tri.md) of the mouth, eyes, and brows, and the turn of the
head.

## Sources and confidence

No public spec describes the whole layout. The starting point was the clean-room
[OpenFaceFX research codec](https://github.com/OpenFaceFX/OpenFaceFX/blob/main/tools/lip_codec_research.py)
(MIT, read at `main` in October 2026). It found the header fields, the 30 frames per
second, and the frame-by-frame grid. It read the body as tokens with "marker" bytes. That
reading fails on about 3,100 vanilla files and misreads about 1% of values in the rest
(values like `-3.6e25`).

OpenSky reads the body as zero-run compressed bytes instead. This was found by probing the
74,070 vanilla lip blocks in `Skyrim - Voices_en0.bsa`.

| Claim | Confidence | Evidence |
| --- | --- | --- |
| 12-byte plain header, then a zero-run compressed body | confirmed | Every vanilla file expands to exactly the declared size |
| Body: frame count, first frame, target count, then the grid | confirmed | Every vanilla file |
| The grid is frame by frame, `slotsPerFrame` values per frame | confirmed | Smooth curves in every slot. All values are finite and small |
| Slots 0 to 15 are the speech targets, in the order below | inferred | The phoneme order of the expression system. Wide 0 to 1 curves |
| Slots 16 to 29 are the modifiers, in the order below | inferred | Slots 16 and 17 are always equal (both eyes blink). So are 22 and 23 (both brows rise). 18 to 21 and 28 to 29 are never used |
| Slots 30, 31, 32 are head pitch, roll, and yaw in radians | inferred | Slot 30 follows look-up minus look-down (correlation 0.99). Slot 32 follows look-left minus look-right (0.97). Values stay within about ±0.16 |
| Positive pitch looks up; positive yaw turns left | inferred | The signs of those correlations |
| The sign of roll | unknown | Nothing on disk shows it |
| Row for audio time `t` is `t * 30 - firstFrame` | inferred | Mouth opening against audio loudness on a sample of lines. The mouth leads the sound by 1 or 2 frames, as in real speech |
| What the 8 creature slots drive | unknown | Dragons, hagravens, and rieklings use them. None has a head TRI |

All integers are little-endian.

## Header

| Offset | Type | Field | Check |
| --- | --- | --- | --- |
| `0x00` | uint32 | Version | Must be `1` |
| `0x04` | uint32 | Expanded size | Body size plus 16 |
| `0x08` | uint32 | Active curve count | Kept, not checked |
| `0x0c` | bytes | Compressed body | To the end of the block |

The expanded size is always the expanded body plus 16 bytes. What the extra 16 count is not
known. The active curve count is 13 in human files and 9 in creature files. It does not
always match the slots in use, and nothing needs it.

## Zero runs

The body is compressed with one rule:

- A `00` byte is followed by a uint16 count. The three bytes stand for that many zero bytes.
- Every other byte stands for itself.

Most of the grid is zeros, so this saves most of the space. A run can end inside a float.
For example, `03 f0 00 01 00 3f` expands to `03 f0 00 3f`, the float `0.5037`. This is why a
token reader gets lost: the bytes `00 01 00` look like a marker, but they are one zero byte.

A count that runs past the declared size, a run cut off at the end, or a body shorter than
the declared size is an error.

## Body

| Offset | Type | Field | Check |
| --- | --- | --- | --- |
| `0x00` | uint32 | Frame count | Not 0 |
| `0x04` | int32 | First frame | `-frameCount` to 18,000 |
| `0x08` | uint32 | Target count | 16 humanoid, 8 creature |
| `0x0c` | float32[] | Grid | `frameCount * slotsPerFrame` values |

`slotsPerFrame` is the grid size divided by `4 * frameCount`, and must be whole. It is 33 in
humanoid files and 8 in creature files.

The older reading saw three "header families". They are one header. A frame count above
255 compresses its zero high byte into the run, and a first frame of 0 joins the zeros
before it. That moved the bytes that follow.

Grid row 0 is at audio frame `firstFrame`. It is negative in almost every vanilla file, so
the grid starts before the audio. Seven vanilla files start it up to 22 frames after the
audio. The duration is `(firstFrame + frameCount) / 30` seconds. Between rows, OpenSky
interpolates linearly, and it holds the first and last rows outside the grid.

## Humanoid slots

The file stores no names. The TRI names below are the spelling in vanilla head TRI files.
A few TRI files spell a name differently (`BMp`, `w`, `BrowDownLEft`), so OpenSky matches
names without case. A TRI without a target, such as `LookLeft` on most heads, leaves that
slot unused.

| Slot | Target | Slot | Target | Slot | Target |
| ---: | --- | ---: | --- | ---: | --- |
| 0 | `Aah` | 11 | `Oh` | 22 | `BrowUpLeft` |
| 1 | `BigAah` | 12 | `OohQ` | 23 | `BrowUpRight` |
| 2 | `BMP` | 13 | `R` | 24 | `LookDown` |
| 3 | `ChJSh` | 14 | `Th` | 25 | `LookLeft` |
| 4 | `DST` | 15 | `W` | 26 | `LookRight` |
| 5 | `Eee` | 16 | `BlinkLeft` | 27 | `LookUp` |
| 6 | `Eh` | 17 | `BlinkRight` | 28 | `SquintLeft` |
| 7 | `FV` | 18 | `BrowDownLeft` | 29 | `SquintRight` |
| 8 | `I` | 19 | `BrowDownRight` | 30 | head pitch |
| 9 | `K` | 20 | `BrowInLeft` | 31 | head roll |
| 10 | `N` | 21 | `BrowInRight` | 32 | head yaw |

Morph weights are clamped to 0 to 1. Brow values reach 1.34 in vanilla files. The head
angles keep their sign and turn the neck and head on top of the clip and of
[head tracking](/engine/head-tracking.md).

The 8-slot creature grids decode, but drive nothing.
