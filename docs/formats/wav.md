---
type: File Format
title: RIFF/WAVE container (.wav)
description: Layout of Skyrim SE .wav sound effects - RIFF chunks, the fmt chunk, the
  sample data, and why OpenSky reads only linear PCM.
tags: [format, audio, wave, riff, pcm]
---

# RIFF/WAVE container (.wav)

Music and voice ship as [`.xwm`](/formats/xwm.md), which holds compressed WMA audio. Every
sound effect (footsteps, doors, hits, creatures) ships as a plain RIFF/WAVE file with
uncompressed linear PCM. There is no codec. OpenSky only turns stored integers into floats.

References:

- Microsoft "Multimedia Programming Interface and Data Specifications 1.0". RIFF framing:
  a 4-character chunk ID, then a little-endian uint32 size. The size does not include the
  8-byte chunk header. A chunk body is padded to an even number of bytes.
- [Microsoft WAVEFORMATEX](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/ns-mmeapi-waveformatex):
  field order and sizes of the `fmt` chunk.

The format chunk ID is `fmt` followed by a space. This page writes it without the space.

## Layout

```text
"RIFF" uint32 size "WAVE"
  "fmt " uint32 size  PCMWAVEFORMAT
  "data" uint32 size  interleaved samples
  ... any other chunk, skipped
```

The first 16 bytes of `fmt`:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint16 | `wFormatTag`. 1 is `WAVE_FORMAT_PCM` |
| 2 | uint16 | `nChannels` |
| 4 | uint32 | `nSamplesPerSec` |
| 8 | uint32 | `nAvgBytesPerSec`. Not used |
| 12 | uint16 | `nBlockAlign`. Not used |
| 14 | uint16 | `wBitsPerSample` |

A longer `fmt` chunk (for example `WAVEFORMATEX` with `cbSize`) is read for its first 16
bytes. The rest is skipped. Other chunks (`fact`, `LIST`, `cue`, tool markers) are skipped
by their size plus the even-byte pad. Mod tools write such chunks.

## Samples

8-bit samples are unsigned. 16-bit samples are signed. This comes from the specification.

| Width | Silence | Conversion to -1...1 |
| --- | --- | --- |
| 8-bit unsigned | 128 | `(raw - 128) / 128` |
| 16-bit signed | 0 | `raw / 32768` |

For sound at a position in the world, OpenSky mixes all channels to mono.
`AVAudioEnvironmentNode` places only mono sounds in 3D. It plays stereo flat. Streamed
`.xwm` sources follow the same rule (see [audio](/engine/audio.md)).

## Which formats OpenSky reads

OpenSky reads linear PCM at 8 or 16 bits. It rejects every other format tag and width. A
sample of 62 vanilla `.wav` files from all archives found only format tag 1 and 16 bits,
mono and stereo, at 8, 11.025, 22.05, 32, and 44.1 kHz. So a mod file in another format is
reported, not played as noise.

If the RIFF size is larger than the file, OpenSky reads up to the end of the file.

## Buffers, not streaming

Music streams because a track is many megabytes of PCM. A sound effect is short. A vanilla
footstep is about 26 KB. So a `.wav` is read whole into one `AVAudioPCMBuffer` and played
once. OpenSky picks the path from the RIFF form type at byte 8: `WAVE` uses a buffer,
`XWMA` streams.
