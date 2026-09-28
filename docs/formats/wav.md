---
type: File Format
title: RIFF/WAVE container (.wav)
description: Layout of Skyrim SE .wav sound effects, and why OpenSky reads only linear PCM.
tags: [format, audio, wave, riff, pcm]
---

# RIFF/WAVE container (.wav)

Skyrim SE stores music and voice as [`.xwm`](/formats/xwm.md), which is compressed WMA.
Every sound effect (footsteps, doors, hits, creatures) is a plain RIFF/WAVE file with
uncompressed linear PCM. PCM means the samples are stored as plain integers.

There is no codec. Reading the file means turning stored integers into floats in [-1, 1].

Sources:

- Microsoft "Multimedia Programming Interface and Data Specifications 1.0". It defines RIFF:
  a four-character chunk ID, a uint32 size that does not count the 8-byte chunk header, and a
  body padded to an even length. It also defines the `WAVE` form with its `fmt` and `data`
  chunks. (The real ID of the format chunk is `fmt` plus a space.)
- [Microsoft WAVEFORMATEX](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/ns-mmeapi-waveformatex):
  field order and sizes in the `fmt` chunk.

## Layout

```text
"RIFF" uint32 size "WAVE"
  "fmt " uint32 size  PCMWAVEFORMAT
  "data" uint32 size  interleaved samples
  ... other chunks, skipped
```

The first 16 bytes of `fmt`:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint16 | `wFormatTag`. 1 means PCM |
| 2 | uint16 | `nChannels` |
| 4 | uint32 | `nSamplesPerSec` |
| 8 | uint32 | `nAvgBytesPerSec`. Not used |
| 12 | uint16 | `nBlockAlign`. Not used |
| 14 | uint16 | `wBitsPerSample` |

A longer `fmt` chunk (WAVEFORMATEX or WAVE_FORMAT_EXTENSIBLE) is read for its first 16 bytes
and then skipped. Unknown chunks, such as `fact`, `LIST`, and `cue`, are skipped by their
size plus the even-byte pad. This keeps files from mod tools readable.

## Samples

8-bit samples are unsigned, and 128 is silence. 16-bit samples are signed, and 0 is silence.
The specification says so.

| Width | Silence | To float |
| --- | --- | --- |
| 8-bit unsigned | 128 | `(raw - 128) / 128` |
| 16-bit signed | 0 | `raw / 32768` |

For 3D sound, OpenSky mixes the channels to mono. `AVAudioEnvironmentNode` places only mono
sounds in space and plays stereo flat. Streamed `.xwm` sounds follow the same rule (see
[audio](/engine/audio.md)).

## Supported formats

OpenSky reads PCM at 8 or 16 bits. Any other format tag or bit width is an error. A sample of
vanilla files, spread over all archives, was all PCM at 16 bits, mono and stereo, at 8,
11.025, 22.05, 32, and 44.1 kHz. So only mods can hit the error, and they get a report
instead of noise.

When the RIFF size is larger than the file, OpenSky reads to the end of the file. It keeps
the chunks that did arrive.

## Buffers, not streaming

Music is minutes long, so OpenSky decodes and plays it in pieces. A sound effect lasts a
fraction of a second. A vanilla footstep file is about 26 KB. So OpenSky reads the whole
effect into one `AVAudioPCMBuffer` and plays it once.

To choose the path, OpenSky reads the RIFF form type at byte 8. `WAVE` uses a buffer. `XWMA`
streams. A buffered sound removes its own audio node when it finishes.
