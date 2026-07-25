---
type: File Format
title: xWMA container (.xwm)
description: On-disk layout of Skyrim SE .xwm audio - RIFF/XWMA framing, the fmt
  WAVEFORMATEX chunk, the dpds packet table, the data payload, and OpenSky's
  frame-only decode policy.
tags: [format, audio, xwma, riff]
timestamp: 2026-07-25T00:00:00Z
---

# xWMA container (.xwm)

Skyrim SE stores its music as `.xwm` files: Microsoft's xWMA container, the RIFF
form XAudio 2 uses to carry a Windows Media Audio stream in packets a console
streaming engine can hand to a hardware decoder. Milestone 9.1.2 frames and
validates that container. It deliberately does **not** decode: the payload and
the codec parameters are handed to the WMA decoder that lands with milestone
9.1.1, and this parser stays a pure container reader.

References used (open sources only — no Bethesda or Microsoft code was read or
transcribed):

* [Microsoft xWMA on MultimediaWiki](https://wiki.multimedia.cx/index.php/Microsoft_xWMA)
  — the community format description: the `RIFF`/`XWMA` form, an 18-byte `fmt`
  chunk holding WAVEFORMATEX, the `dpds` table ("the i-th integer equals the
  total number of bytes accumulated after the i-th packet in the data structure
  has been decoded"), and a `data` chunk of `nBlockAlign`-sized packets.
* [FFmpeg `libavformat/xwma.c`](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/xwma.c)
  — read as documentation, not copied. It supplies the magic and form-type
  checks, the `dpds` element width and the rejection of a second `dpds` chunk,
  the fact that packets are `nBlockAlign` bytes with a possibly short final
  packet, and the duration formula (last `dpds` entry divided by
  `nChannels * wBitsPerSample / 8`).
* [Microsoft WAVEFORMATEX](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/ns-mmeapi-waveformatex)
  — field order and widths of the `fmt` chunk.
* Microsoft "Multimedia Programming Interface and Data Specifications 1.0" —
  RIFF framing: a four-character chunk id, a little-endian `uint32` size that
  excludes the 8-byte chunk header, and bodies padded to an even byte count.

Impl: `opensky/Formats/XWM/XWMFile.swift` (codec policy and derived values) plus
`opensky/Formats/XWM/XWMChunkScan.swift` (the RIFF walk). All integers are
little-endian.

## File header — first 12 bytes

| offset | type   | field    | notes                                          |
| ------ | ------ | -------- | ---------------------------------------------- |
| 0x00   | char4  | Magic    | `RIFF`                                         |
| 0x04   | uint32 | RIFFSize | bytes after this field, i.e. file size minus 8 |
| 0x08   | char4  | FormType | `XWMA`                                         |

Everything after the header is a sequence of chunks. Each chunk is a
four-character id, a `uint32` body size that excludes the 8-byte chunk header,
the body, and a pad byte when the body length is odd.

## `fmt` chunk — WAVEFORMATEX, 18 bytes

The chunk id is four characters, `f`, `m`, `t` and a space; markdown lint
strips the trailing space inside inline code, so it is written `fmt` below.

| offset | type   | field           | notes                                       |
| ------ | ------ | --------------- | ------------------------------------------- |
| 0x00   | uint16 | wFormatTag      | `0x0161` = WAVE_FORMAT_WMAUDIO2 (WMAv2)     |
| 0x02   | uint16 | nChannels       | 2 throughout vanilla Skyrim SE              |
| 0x04   | uint32 | nSamplesPerSec  | decoded PCM sample rate in hertz            |
| 0x08   | uint32 | nAvgBytesPerSec | nominal byte rate; times 8 is the bit rate  |
| 0x0C   | uint16 | nBlockAlign     | size of one encoded packet in `data`        |
| 0x0E   | uint16 | wBitsPerSample  | bit depth of the *decoded* PCM, not of the packets |
| 0x10   | uint16 | cbSize          | codec extradata that follows; 0 in vanilla  |

`wBitsPerSample` describes the decoder's output, not the encoded stream: the
container has no per-sample width of its own. `nBlockAlign` is the packet
stride, which is what makes streaming possible without decoding anything.

OpenSky accepts `wFormatTag == 0x0161` only. `0x0162`
(WAVE_FORMAT_WMAUDIO3, WMA Pro) and `0x0163` (WMA Lossless) are recognized and
raise `XWMError.unsupported`; any other tag raises `unsupported` as well.
FFmpeg notes that xWMA normally carries WMAv2 with one or two channels or WMA
Pro with six, so the WMA Pro case is a real variant rather than corruption — it
just does not occur in the vanilla corpus and would need a decoder path OpenSky
has not written.

## `dpds` chunk — decoded packet cumulative data size

A run of `uint32` values, one per encoded packet, each the total number of
decoded PCM **bytes** accumulated once that packet has been decoded. It is the
container's seek index: dividing an entry by
`nChannels * wBitsPerSample / 8` converts it to a sample-frame position, and the
matching byte offset in `data` is `(index + 1) * nBlockAlign`.

The last entry is therefore the total decoded size, which is where the file's
duration comes from. OpenSky exposes it as `declaredDecodedByteCount`,
`declaredSampleCount` and `declaredDuration`, all optional because the chunk is
optional. A chunk size that is not a multiple of four is rejected as malformed;
a second `dpds` chunk is rejected too, since two tables cannot both index one
payload.

## `data` chunk — encoded payload

The WMA bitstream, split into `nBlockAlign`-sized packets. The final packet may
be short; FFmpeg clamps its read to what is left rather than dropping it, and so
does `XWMFile.packet(at:)`. An empty `data` chunk is malformed.

## Validation and error policy

`XWMError.malformed` means the input violates the layout above;
`XWMError.unsupported` means a structurally valid file in a variant OpenSky
declines. Both are typed and `Equatable`; nothing traps, force-unwraps or reads
out of bounds, which the synthetic fixture tests in
`openskyTests/XWMFileTests.swift` pin down: truncated header, wrong magic or
form type, truncated payload, a chunk length overrunning the file, a RIFF size
overrunning the buffer, a missing `fmt` or `data` chunk, duplicate chunks, an
unexpected format tag, a zero-length payload, a short `fmt` chunk,
out-of-range WAVEFORMATEX fields, and a misaligned `dpds` chunk.

Two things are reported rather than rejected, because both are legal:

* a file with no `dpds` chunk at all (no declared duration, still playable), and
* a `dpds` entry count that does not match the payload's packet count
  (`isPacketTableConsistent` is advisory; the sweep counts mismatches).

Unknown chunk ids are skipped, as RIFF requires.

## Decode policy

This parser never decodes. It exposes exactly what a decoder needs:

* `codec: XWMCodecParameters` — `formatTag`, `channelCount`, `sampleRate`,
  `averageBytesPerSecond`, `blockAlign`, `bitsPerSample`, `extraData`, plus the
  derived `bitRate` and `bytesPerDecodedFrame`.
* `payload: Data` and `packet(at:)` — the encoded bytes, whole or per packet, so
  a decoder can stream without the container holding a second copy.
* the `dpds` table and the declared byte, sample and duration counts, for
  seeking and for checking a decode against what the container claimed.

Note for the decoder: vanilla `.xwm` carries `cbSize == 0`, so `extraData` is
empty, while the WMA codecs want extradata. FFmpeg's xWMA demuxer synthesizes a
six-byte WMAv2 extradata block with byte 4 set to 31, describing it as an
experimentally obtained value. That substitution is a decoder-side policy
decision and deliberately does not live in this parser.

## Vanilla sweep evidence

`openskycli audio sweep` frames every `.xwm` the archives provide, streaming one
file at a time (counts only, no file bytes retained). Vanilla Skyrim SE
archives, 2026-07-25:

| measure                | value                                        |
| ---------------------- | -------------------------------------------- |
| files                  | 269 (all under `music\`)                     |
| framed                 | 269                                          |
| unsupported / failed   | 0 / 0                                        |
| format tag             | `0x0161` x269                                |
| channels               | 2 x269                                       |
| sample rates           | 32000 x133, 44100 x135, 48000 x1             |
| block align            | 1008 x1, 2230 x135, 2304 x133                |
| cbSize                 | 0 x269                                       |
| files without `dpds`   | 0                                            |
| `dpds`/packet mismatch | 0                                            |
| partial final packet   | 0                                            |
| payload                | 125,908,870 bytes, 347.0 minutes declared    |

No file names or bytes leave the install; the sweep prints counts and per-file
summary lines only. The tally line carries a `decoded` column that stays 0 until
the WMA decoder lands (milestone 9.1.1) — the probe grep gates `0 failed`, so
the line shape does not change when decoding is wired in.

Sample rate and block align pair up: 2230-byte packets go with 44.1 kHz,
2304-byte packets with 32 kHz. The single 48 kHz file with 1008-byte packets is
the outlier and still frames cleanly.

## Out of scope

`.fuz` (voice) is milestone M17 voice work, not this parser — 75,408 archive
entries the sweep does not touch. Sound effects are 5,978 plain `.wav` entries
and do not go through this path either. Only the 269 `.xwm` music files use the
xWMA container.
