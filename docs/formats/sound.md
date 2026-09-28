---
type: File Format
title: Sound records
description: Skyrim SE SNDR, SNCT, and SOUN fields, the category tree, and sound file paths.
tags: [format, plugin, audio, sound]
---

# Sound records

Three records describe sounds:

- `SNDR`, a sound descriptor: the sound files and how to play them.
- `SNCT`, a sound category: a node in the volume mixer tree, for example "Footsteps".
- `SOUN`, a sound marker: a placed object that names one `SNDR`.

Sources: UESP [`SNDR`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SNDR),
[`SNCT`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SNCT), and
[`SOUN`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SOUN). Field sizes and signs
checked against xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).
The Creation Kit page [Sound Descriptor](https://ck.uesp.net/wiki/Sound_Descriptor) explains
what the settings do.

## SNDR

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `CNAM` | uint32 | Descriptor type |
| `GNAM` | FormID | Sound category (`SNCT`) |
| `SNAM` | FormID | Alternate descriptor |
| `ANAM` | zstring | One sound file path. Repeats, in order |
| `ONAM` | FormID | Output model |
| `LNAM` | 4 bytes | Looping, in byte 1 |
| `BNAM` | 6 bytes | Below |

`LNAM` byte 1: `0` no loop, `8` loop, `16` fast envelope, `32` slow envelope. OpenSky keeps
any other value as unknown. It does not guess what it means.

`BNAM`:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | int8 | Frequency shift, percent |
| 1 | int8 | Frequency variance, percent |
| 2 | uint8 | Priority |
| 3 | uint8 | Decibel variance |
| 4 | uint16 | Static attenuation, in 1/100 dB |

## SNCT

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `FNAM` | uint32 | Flags: bit 0 mute under water, bit 1 show in menu |
| `PNAM` | FormID | Parent `SNCT` |
| `VNAM` | uint16 / 65535 | Static volume multiplier |
| `UNAM` | uint16 / 65535 | Default menu value |

The `PNAM` links form a tree. To find a sound's volume slider, OpenSky starts at
`SNDR GNAM` and walks up the parents to the first node shown in the menu. A broken mod can
make a loop, so the walk stops at a node it has seen. If no menu node is found, the sound
uses Effects.

`Skyrim.esm` has 18 `SNCT` records. Four are shown in the menu:

| `SNCT` editor ID | English label | OpenSky category |
| --- | --- | --- |
| `AudioCategorySFX` | Effects | `effects` |
| `AudioCategoryVOCGeneral` | Voice | `voice` |
| `AudioCategoryMUS` | Music | `music` |
| `AudioCategoryFST` | Footsteps | `footsteps` |

`_AudioCategoryMaster` is the root. OpenSky uses it as the master volume, not as a category.
OpenSky reads `VNAM` and `UNAM` but does not use them. Its volume model and defaults are its
own.

## SOUN

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `SDSC` | FormID | The `SNDR` to play |

Skyrim SE uses `SDSC`. OpenSky ignores the older `SOUN FNAM` and `SOUN SNDD` layouts.

## Sound file paths

The Creation Kit writes `ANAM` paths in several forms. A path may be relative to
`Data\Sound`, may start with `Sound`, or may start with a separator before either. The
leading separator means "from the root" on Windows. It is not a drive. So OpenSky:

1. Removes a leading separator and an outer `Data\`.
2. Adds `sound\` in front if it is missing.
3. Applies the [VFS path rules](/formats/vfs.md): backslashes, lowercase, no unsafe parts.
4. Drops a path that still has a `:`, because that is a drive path.

A dropped path does not change the order of the others.

In `Skyrim.esm`, about 300 `ANAM` paths start with a separator. Two are real `C:` paths from
an author's machine, and OpenSky drops them. Almost all other paths resolve through the VFS.
About 20 name development files that the game does not ship.

## Field sizes

`SNCT FNAM`, `PNAM`, `VNAM`, `UNAM`, `SNDR LNAM`, `BNAM`, and `SOUN SDSC` are read only at
their exact documented sizes. Other sizes are ignored. This keeps a broken field from
moving later reads.
