---
type: File Format
title: xWMA container (.xwm)
description: Layout of Skyrim SE .xwm audio (RIFF/XWMA framing, the fmt chunk, the dpds packet
  table, the data payload), and why the parser does not decode.
tags: [format, audio, xwma, riff]
---

# xWMA container (.xwm)

Skyrim SE stores music as `.xwm` files. The format is Microsoft's xWMA container. It is a
RIFF file that carries a Windows Media Audio (WMA) stream in fixed-size packets.

The parser only reads the container. It does not decode audio. It hands the packets and the
codec settings to the WMA decoder (see [audio](/engine/audio.md)).

Sources (open sources only, no Bethesda or Microsoft code):

- [Microsoft xWMA on MultimediaWiki](https://wiki.multimedia.cx/index.php/Microsoft_xWMA):
  the `RIFF`/`XWMA` form, an 18-byte `fmt` chunk, the `dpds` table, and a `data` chunk of
  `nBlockAlign`-sized packets. About `dpds`: "the i-th integer equals the total number of
  bytes accumulated after the i-th packet in the data structure has been decoded".
- [FFmpeg `libavformat/xwma.c`](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/xwma.c),
  read as documentation, not copied. It gives the magic checks, the `dpds` element size, the
  rule against a second `dpds`, the short final packet, and the duration formula.
- [Microsoft WAVEFORMATEX](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/ns-mmeapi-waveformatex):
  field order and sizes of `fmt`.
- Microsoft "Multimedia Programming Interface and Data Specifications 1.0": RIFF chunks. A
  chunk is a four-character ID, a uint32 size (not counting the 8-byte chunk header), the
  body, and a pad byte when the body length is odd.

All integers are little-endian.

## File header (12 bytes)

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | char4 | Magic | `RIFF` |
| 0x04 | uint32 | RIFFSize | File size minus 8 |
| 0x08 | char4 | FormType | `XWMA` |

Chunks follow the header. Unknown chunks are skipped, as RIFF requires.

## fmt chunk (18 bytes)

The real chunk ID is `fmt` followed by a space.

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | uint16 | wFormatTag | `0x0161` is WMAv2 |
| 0x02 | uint16 | nChannels | 2 in all vanilla files |
| 0x04 | uint32 | nSamplesPerSec | Sample rate of the decoded audio |
| 0x08 | uint32 | nAvgBytesPerSec | Times 8 is the bit rate |
| 0x0C | uint16 | nBlockAlign | Size of one packet in `data` |
| 0x0E | uint16 | wBitsPerSample | Bit depth of the decoded audio, not of the packets |
| 0x10 | uint16 | cbSize | Size of codec extra data after this. 0 in vanilla |

`nBlockAlign` is the packet size. It lets a player stream the file without decoding it
first.

OpenSky accepts only `0x0161`. `0x0162` (WMA Pro) and `0x0163` (WMA Lossless) are reported as
not supported. FFmpeg says xWMA can also carry WMA Pro with six channels. So WMA Pro is a
real variant, not damage. Vanilla just does not use it.

## dpds chunk (packet table)

A list of uint32 values, one per packet. Each value is the total number of decoded bytes
after that packet. It is the seek index:

- Divide an entry by `nChannels * wBitsPerSample / 8` to get a sample frame position.
- The matching position in `data` is `(index + 1) * nBlockAlign`.
- The last entry is the total decoded size. That gives the duration.

Example: a stereo 16-bit file whose last entry is 1764000. One frame is 2 x 16 / 8 = 4 bytes,
so there are 441000 frames. At 44100 Hz that is 10 seconds.

A `dpds` size that is not a multiple of 4 is an error. A second `dpds` chunk is an error too,
because two tables cannot index one payload.

## data chunk

The WMA stream, split into `nBlockAlign`-sized packets. The last packet may be shorter.
OpenSky keeps it, as FFmpeg does. An empty `data` chunk is an error.

## Errors

A malformed file is an error: bad header, wrong magic, a chunk that runs past the end, a
missing `fmt` or `data`, duplicate chunks, a short `fmt`, or out-of-range `fmt` values. A
valid file in a variant OpenSky does not handle is a separate "unsupported" error.

Two cases are legal and only reported:

- No `dpds` chunk. The file has no stated duration but still plays.
- A `dpds` entry count that does not match the packet count.

## Extra data for the decoder

Vanilla files have `cbSize == 0`, so there is no extra data. But WMA decoders expect it.
FFmpeg's xWMA reader builds a six-byte WMAv2 extra data block with byte 4 set to 31. FFmpeg
calls it "experimentally obtained". This choice belongs to the decoder, not the container
parser.

## Vanilla files

`openskycli audio sweep` reads every `.xwm` in the archives, one at a time. In vanilla:

- All `.xwm` files are music, under `music\`. All are WMAv2, stereo, with `cbSize` 0 and a
  consistent `dpds` table.
- Sample rate and packet size go together. 2230-byte packets go with 44.1 kHz. 2304-byte
  packets go with 32 kHz. One file uses 48 kHz with 1008-byte packets.
- Every file decodes, and the decoded frame count equals what its `dpds` table says.

Voice lines are `.fuz` files, which wrap one xWMA file each (see [FUZ](/formats/fuz.md)). Sound
effects are `.wav` files (see [WAV](/formats/wav.md)).
