---
type: File Format
title: Sound output and reverb records
description: Skyrim SE SOPM sound output models and REVB reverb parameters.
tags: [format, plugin, audio]
---

# Sound output and reverb records

`SOPM` says how a sound reaches the speakers. `REVB` says how a room colors it. See
[sound](/formats/sound.md) for the descriptors that use them.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## SOPM

| Field | Type | Meaning |
| --- | --- | --- |
| `NAM1` | 4 bytes | Byte 0 flags (0x01 attenuates with distance, 0x02 allows rumble), byte 3 reverb send percent |
| `MNAM` | uint32 | Type: 0 uses HRTF, 1 defined speaker output |
| `ONAM` | 24 bytes | Speaker levels: 3 input channels (mono, stereo left, stereo right) by 8 speakers (L, R, C, LFE, RL, RR, BL, BR) |
| `ANAM` | 20 bytes | Attenuation: 4 unused bytes, min and max distance (floats), 5 curve points (0 to 100), 1 unused byte |
| `FNAM`, `CNAM`, `SNAM` | bytes | Leftovers xEdit marks unused, kept raw |

## REVB

`DATA` is 14 bytes in all 11 records.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint16 | Decay time, ms |
| 2 | uint16 | HF reference, Hz |
| 4 | int8 | Room filter |
| 5 | int8 | Room HF filter |
| 6 | int8 | Reflections |
| 7 | int8 | Reverb amplitude |
| 8 | uint8 | Decay HF ratio, in hundredths |
| 9 | uint8 | Reflect delay, scaled |
| 10 | uint8 | Reverb delay, ms |
| 11 | uint8 | Diffusion, percent |
| 12 | uint8 | Density, percent |
| 13 | uint8 | Not named |
