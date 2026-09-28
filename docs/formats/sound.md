---
type: File Format
title: Sound records
description: SNDR, SNCT, and SOUN fields, the sound category tree, and how track paths resolve.
tags: [format, plugin, audio, sound]
---

# Sound records

Three records describe sounds:

- `SOUN` is a sound marker. It names one descriptor.
- `SNDR` is a sound descriptor. It lists the sound files and how to play them.
- `SNCT` is a sound category. Categories form a tree, which is the game's volume mixer.

Sources: UESP [`SNDR`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SNDR),
[`SNCT`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SNCT), and
[`SOUN`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SOUN). Field sizes and signs
were checked against xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).
The Creation Kit page [Sound Descriptor](https://ck.uesp.net/wiki/Sound_Descriptor)
explains what the settings mean.

## SNDR sound descriptor

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `CNAM` | uint32 | Descriptor type |
| `GNAM` | FormID | Sound category |
| `SNAM` | FormID | Alternate descriptor |
| `ANAM` | zstring | One sound file path. Repeats, in order |
| `ONAM` | FormID | Output model |
| `LNAM` | 4 bytes | Looping, in byte 1 |
| `BNAM` | 6 bytes | Frequency, priority, variance, attenuation |

`LNAM` byte 1: `0` no loop, `8` loop, `16` fast envelope, `32` slow envelope. OpenSky keeps
any other value as unknown.

`BNAM`:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | int8 | Frequency shift, percent |
| 1 | int8 | Frequency variance, percent |
| 2 | uint8 | Priority |
| 3 | uint8 | Decibel variance |
| 4 | uint16 | Static attenuation, in hundredths of a decibel |

Example: a stored attenuation of 350 is 3.5 dB.

## SNCT sound category

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `FNAM` | uint32 | Flags: bit 0 mute under water, bit 1 show in the menu |
| `PNAM` | FormID | Parent `SNCT` |
| `VNAM` | uint16 / 65535 | Static volume multiplier |
| `UNAM` | uint16 / 65535 | Default menu value |

OpenSky starts at `SNDR.GNAM` and follows `PNAM` upward. The first category that shows in
the menu gives the sound its volume slider. A loop, a missing node, or an unknown name gives
no slider, and the sound uses Effects.

`Skyrim.esm` has 18 categories. Four show in the menu:

| `SNCT.EDID` | Label | OpenSky category |
| --- | --- | --- |
| `AudioCategorySFX` | Effects | `effects` |
| `AudioCategoryVOCGeneral` | Voice | `voice` |
| `AudioCategoryMUS` | Music | `music` |
| `AudioCategoryFST` | Footsteps | `footsteps` |

`_AudioCategoryMaster` is the root. OpenSky uses it as the separate master volume.
OpenSky reads `VNAM` and `UNAM` but does not apply them. Its volume is master x category x
source x fade, with its own defaults.

## SOUN sound marker

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `SDSC` | FormID | The `SNDR` descriptor |

The older `SOUN FNAM` and `SOUN SNDD` fields are ignored. Skyrim SE uses `SDSC`.

## Track paths

Each `ANAM` path is resolved in order. The Creation Kit writes these paths in several forms:

- relative to `Data\Sound`: `fx\door\door01.wav`
- starting at `Sound`: `sound\fx\door\door01.wav`
- with a leading separator: `\sound\fx\door\door01.wav`
- with an outer `Data\`

The leading separator means "from the root" on Windows. It is not a drive. OpenSky removes it
and an outer `Data\`, and adds `sound\` when missing. Then the
[VFS path rules](/formats/vfs.md) apply. A path that still has a `:` names a drive, such as
`C:`, and is dropped. A bad path is dropped without changing the order of the others.

In `Skyrim.esm`, about 6% of the paths start with a separator. Two paths name a `C:` drive
on the authoring machine. After these rules, almost every path resolves. The few that do not
name development files that never shipped.

## Bad input

Each decoder checks its record type. Unknown fields are skipped. The fixed-size fields
(`SNCT FNAM`, `PNAM`, `VNAM`, `UNAM`, `SNDR LNAM`, `BNAM`, `SOUN SDSC`) are read only at
their exact size. Any other size is ignored.
