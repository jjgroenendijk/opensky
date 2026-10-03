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

## Output model mapping

| `SOPM` value | OpenSky playback |
| --- | --- |
| Type 0 (HRTF) | 3D source on the environment node |
| Type 1 (speaker output) | Flat source on the category submix. The speaker matrix is not used |
| No model, or no type | Mono plays in 3D, wider files play flat |
| Flag 0x01 | The `ANAM` curve sets the gain: five points spread evenly from the minimum to the maximum distance, linear between them, full gain inside the minimum |
| Reverb send percent | The source's reverb blend, 0 to 1 |

Type 1 sounds on the install still set flag 0x01, so a flat sound can still fade with
distance. A curve source in 3D is placed at the reference distance in its true direction, so
the node's own distance model adds nothing and the curve alone sets loudness.

## Reverb mapping

An interior's acoustic space (`ASPC BNAM`) names a `REVB`. Apple's reverb unit has no decay
or delay controls, so the decay time picks the nearest factory room:

| Decay time | Room |
| --- | --- |
| Under 400 ms | Small room |
| 400 to 999 ms | Medium room |
| 1000 to 1999 ms | Large room |
| 2000 to 2999 ms | Medium hall |
| 3000 to 3499 ms | Large hall |
| 3500 ms and up | Cathedral |

The wet level is the room filter plus the reverb amplitude, in dB, clamped to -40 to 40. A
zero decay, or a room or reverb gain at -60 dB or lower, switches reverb off. Outdoors there is
no reverb. On the install, interior records span room filters -1 to -13 dB, reverb
amplitudes 0 to 17 dB, and decays 193 to 3987 ms; `DefaultReverb` (-100 dB, 0 ms) means off.

A change fades the wet level at 40 dB/s. A change of room first fades out, then switches the
preset, then fades in, so the preset never jumps under a loud tail. The Audio panel's reverb
section can hold the wet level at a fixed value for a listening test.
