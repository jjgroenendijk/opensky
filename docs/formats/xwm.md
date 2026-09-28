---
type: File Format
title: xWMA container (.xwm)
description: Layout of Skyrim SE .xwm audio - RIFF/XWMA framing, the fmt chunk, the dpds
  packet table, and the data payload.
tags: [format, audio, xwma, riff]
---

# xWMA container (.xwm)

Skyrim SE stores its music as `.xwm` files. xWMA is a Microsoft RIFF container for XAudio 2.
It holds a Windows Media Audio (WMA) stream cut into packets of equal size. The container
parser only reads the framing. A separate WMA decoder turns the packets into sound (see
[audio](/engine/audio.md)).

References. No Bethesda or Microsoft code was used.

- [Microsoft xWMA on MultimediaWiki](https://wiki.multimedia.cx/index.php/Microsoft_xWMA):
  the `RIFF`/`XWMA` form, an 18-byte `fmt` chunk with `WAVEFORMATEX`, the `dpds` table
  ("the i-th integer equals the total number of bytes accumulated after the i-th packet in
  the data structure has been decoded"), and a `data` chunk of `nBlockAlign`-sized packets.
- [FFmpeg `libavformat/xwma.c`](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/xwma.c),
  read as documentation, not copied: the magic and form type checks, the `dpds` element
  size, the rule that a second `dpds` is an error, the short last packet, and the duration
  formula.
- [Microsoft WAVEFORMATEX](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/ns-mmeapi-waveformatex):
  field order and sizes of `fmt`.
- Microsoft "Multimedia Programming Interface and Data Specifications 1.0": RIFF framing
  (4-character ID, uint32 size without the 8-byte chunk header, even-byte padding).

All integers are little-endian.

## File header: 12 bytes

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | char4 | Magic | `RIFF` |
| 0x04 | uint32 | RIFFSize | File size minus 8 |
| 0x08 | char4 | FormType | `XWMA` |

Chunks follow. Each chunk is a 4-character ID, a uint32 body size (without the 8-byte chunk
header), the body, and one pad byte when the body size is odd. Unknown chunks are skipped.

## `fmt` chunk: WAVEFORMATEX, 18 bytes

The chunk ID is `fmt` followed by a space. Markdown lint removes a trailing space in inline
code, so this page writes `fmt`.

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | uint16 | wFormatTag | `0x0161` is `WAVE_FORMAT_WMAUDIO2` (WMA version 2) |
| 0x02 | uint16 | nChannels | 2 in all vanilla files |
| 0x04 | uint32 | nSamplesPerSec | Sample rate of the decoded sound, in hertz |
| 0x08 | uint32 | nAvgBytesPerSec | Byte rate. Times 8 gives the bit rate |
| 0x0C | uint16 | nBlockAlign | Size of one packet in `data` |
| 0x0E | uint16 | wBitsPerSample | Bits per sample of the decoded sound, not of the packets |
| 0x10 | uint16 | cbSize | Size of codec extra data that follows. 0 in vanilla |

OpenSky reads only `wFormatTag == 0x0161`. `0x0162` (WMA Pro) and `0x0163` (WMA Lossless)
are recognized but not supported. FFmpeg notes that xWMA normally holds WMA version 2 with
one or two channels, or WMA Pro with six. So WMA Pro is a real variant, not a broken file.
Vanilla does not use it.

Vanilla files have `cbSize == 0`, so there is no extra data. The WMA decoder needs extra
data. FFmpeg's xWMA reader makes a six-byte WMA version 2 block with byte 4 set to 31, and
calls this value "experimentally obtained". OpenSky's decoder does the same. The container
parser does not.

## `dpds` chunk: packet table

A list of uint32 values, one per packet. Each value is the total number of decoded bytes
after that packet is decoded. It is the seek table: divide a value by
`nChannels * wBitsPerSample / 8` to get a sample frame position. The matching byte offset
in `data` is `(index + 1) * nBlockAlign`.

The last value is the total decoded size, so it gives the duration. The chunk is optional.

- A `dpds` size that is not a multiple of 4 is an error.
- A second `dpds` chunk is an error, because two tables cannot both describe one payload.
- A missing `dpds` is allowed. The file has no stated duration but still plays.
- A `dpds` count that does not match the packet count is allowed and reported.

## `data` chunk: packets

The WMA stream, cut into `nBlockAlign`-sized packets. The last packet may be short. FFmpeg
reads what is left instead of dropping it, and so does OpenSky. An empty `data` chunk is an
error.

## Vanilla files

`openskycli audio sweep` reads every `.xwm` in the archives, one file at a time, and prints
only counts.

| Measure | Value |
| --- | --- |
| Files | 269, all under `music\` |
| Format tag | `0x0161` in all |
| Channels | 2 in all |
| Sample rates | 32000 x 133, 44100 x 135, 48000 x 1 |
| Block align | 1008 x 1, 2230 x 135, 2304 x 133 |
| cbSize | 0 in all |
| Files without `dpds` | 0 |
| `dpds` and packet count differ | 0 |
| Short last packet | 0 |
| Total | about 126 MB, 347 minutes |

Sample rate and block align go together: 2230-byte packets with 44.1 kHz, and 2304-byte
packets with 32 kHz. One 48 kHz file with 1008-byte packets is different, and it still
reads. All 269 files decode, and each decoded frame count equals what its `dpds` table says.

Only music uses xWMA. Voice uses [`.fuz`](/formats/fuz.md), and sound effects use plain
[`.wav`](/formats/wav.md).
