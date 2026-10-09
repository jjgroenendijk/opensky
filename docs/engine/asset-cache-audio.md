---
type: Subsystem
title: Asset cache audio
description: Why the asset cache stores no audio, and the AAC transparency check that
  rules out lossy copies.
tags: [engine, assets, cache, audio]
---

# Asset cache audio

The [asset cache](/engine/asset-cache.md) stores no audio: a lossless ALAC copy decodes at
the same CPU cost as the shipped xWMA, so it loads no faster.

AAC is smaller but lossy, so a lossy copy could only be used where it makes no audible
difference. `openskycli audio aac-check` measures that per sound category instead of a
listening test:

- Categories, from the folder: `music`, `voice` (`sound\fx\voc`; dialogue is `.fuz` and is
  not cached), `ambience` (`sound\fx\amb*`), and `effects` (the rest).
- Each sampled sound is encoded as AAC at 96 kbps per channel, decoded, and compared with
  the original. The measure is the band spectral distortion (SD): per 1024-sample frame, the
  root mean square of the level difference in the 24 Bark critical bands (Zwicker 1961).
  Frames quieter than -50 dBFS are skipped, and a band more than 60 dB below the loudest
  band of its frame is masked.
- A sound is transparent by the Paliwal and Atal (1993) rule: mean SD under 1 dB, under 2 %
  of frames from 2 to 4 dB, and no frame over 4 dB. A category may use AAC only when every
  sampled sound is transparent.
- AAC defines a fixed set of sampling rates. A few vanilla sounds use 22000 Hz, so they stay
  ALAC in any category.

Result, 400 sounds per category at most (2026-10-07, run directory
`.logs/aac-check/20261007T020728Z`):

| Category | Sounds | Transparent | Mean SD | Worst sound |
| --- | --- | --- | --- | --- |
| Effects | 399 | 387 | 0.33 dB | 1.23 dB |
| Voice | 122 | 120 | 0.28 dB | 0.51 dB |
| Ambience | 387 | 269 | 0.47 dB | 2.47 dB |
| Music | 116 | 115 | 0.10 dB | 0.35 dB |

No category passes. The failing sounds fail on a few frames at a sharp attack, where AAC
spreads noise before the attack (pre-echo). At 128 kbps per channel the counts barely change
(run `.logs/aac-check/20261007T021023Z`), so a higher rate is not the fix.
