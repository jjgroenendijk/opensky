---
type: File Format
title: RIFF/WAVE container (.wav)
description: On-disk layout of Skyrim SE .wav sound effects - RIFF framing, the fmt
  PCMWAVEFORMAT chunk, the data payload, and OpenSky's linear-PCM-only policy.
tags: [format, audio, wave, riff, pcm]
timestamp: 2026-08-04T00:00:00Z
---

# RIFF/WAVE container (.wav)

Skyrim SE splits its audio by role. Music and voice ship as
[`.xwm`](/formats/xwm.md), the xWMA container carrying a compressed WMA stream. Every
sound *effect* — footsteps, doors, impacts, creature noises — ships as a plain RIFF/WAVE
file holding uncompressed linear PCM. The install carries 5,978 of them.

There is no codec here. A `wFormatTag` of 1 means the samples are stored as they are, so
"decoding" is widening stored integers into the normalized floats `AVAudioPCMBuffer`
wants. That is the whole parser.

References used (open sources only):

* Microsoft "Multimedia Programming Interface and Data Specifications 1.0" — RIFF
  framing: a four-character chunk id, a little-endian `uint32` size that excludes the
  8-byte chunk header, and bodies padded to an even byte count; the `WAVE` form and its
  `fmt` and `data` chunks. Chunk ids are four characters, so the format chunk's id is
  `fmt` followed by a space; it is written without the trailing space throughout this page.
* [Microsoft WAVEFORMATEX](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/ns-mmeapi-waveformatex)
  — field order and widths of the `fmt` chunk.

Impl: `opensky/Formats/WAV/WAVFile.swift`; playback in
`opensky/Audio/WorldAudioEngineWAV.swift`.

## Layout

```text
"RIFF" uint32 size "WAVE"
  "fmt " uint32 size  PCMWAVEFORMAT
  "data" uint32 size  interleaved samples
  ... any other chunk, skipped
```

`fmt`, the 16 bytes this reader uses:

| offset | type | meaning |
| --- | --- | --- |
| 0 | uint16 | `wFormatTag`; 1 is WAVE_FORMAT_PCM |
| 2 | uint16 | `nChannels` |
| 4 | uint32 | `nSamplesPerSec` |
| 8 | uint32 | `nAvgBytesPerSec`, derivable and unused |
| 12 | uint16 | `nBlockAlign`, derivable and unused |
| 14 | uint16 | `wBitsPerSample` |

A `fmt` chunk longer than 16 bytes (WAVEFORMATEX adds `cbSize`, WAVE_FORMAT_EXTENSIBLE
adds more) is read for its first 16 bytes and then skipped to its declared end. Chunks
this reader does not know — `fact`, `LIST`, `cue`, authoring-tool markers — are skipped
by their declared size plus the RIFF even-byte pad, which is what keeps the walk working
on files a mod tool wrote.

## Sample widening

8-bit WAVE samples are **unsigned**, with 128 as silence; 16-bit samples are
two's-complement **signed**, with 0 as silence. That difference is the specification's,
not a quirk, and it is the only place the two widths differ beyond their size:

| stored width | silence | normalization |
| --- | --- | --- |
| 8-bit unsigned | 128 | `(raw - 128) / 128` |
| 16-bit signed | 0 | `raw / 32768` |

Samples come out interleaved, one `Float` per sample in [-1, 1]. The positional playback
path averages the channels to mono because `AVAudioEnvironmentNode` spatializes mono
inputs and passes stereo through flat — the same rule
[`AudioSourceStreamer`](/engine/audio.md) follows for streamed `.xwm` sources.

## Format policy

Linear PCM at 8 or 16 bits is read; every other tag and width is declined with
`WAVError.unsupportedFormat` rather than guessed at.

A read-only sweep of 62 `.wav` files sampled evenly across the install's archives on
2026-08-04 found `wFormatTag` 1 and `wBitsPerSample` 16 in every one, mono and stereo, at
8 kHz, 11.025 kHz, 22.05 kHz, 32 kHz and 44.1 kHz. So the declined cases are formats
vanilla does not use, and a mod that does use one is reported instead of played back as
noise. A truncated file whose RIFF size overruns the buffer is clamped to the buffer
rather than refused, so whatever chunks did arrive are still read.

## Why buffers and not streaming

`.xwm` music streams: a track is minutes long and tens of megabytes of PCM, so the engine
decodes a chunk, schedules it, and repeats (issue #218). A `.wav` effect is a fraction of
a second — the vanilla footstep files are around 26 KB — so it is read whole into one
`AVAudioPCMBuffer` and scheduled once. Streaming it would add a decode-queue hop and a
three-buffer lookahead to something that fits in a single scheduling call.

`WorldAudioEngine.playPositional(fileData:)` and its non-positional twin pick the path by
peeking at the RIFF form type at byte 8: `WAVE` takes the buffer path, `XWMA` the
streamed one. A buffer source retires itself through the scheduling completion handler,
so a one-shot effect leaves no node attached behind it.
