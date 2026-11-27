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
| `SNAM` | uint32 | Kept as a raw number; nothing reads it while the game runs |
| `ANAM` | zstring | One sound file path. Repeats, in order |
| `ONAM` | FormID | Output model |
| `FNAM` | uint32 | Older flags, below |
| `LNAM` | 4 bytes | Looping in byte 1, rumble send in byte 3 |
| `BNAM` | 6 bytes | Below |

When a descriptor with several `ANAM` files plays, the game picks one at random. If the pick is the
file this descriptor played last, it takes the next one in the list instead, wrapping round to the
first. The last file played is kept on the descriptor, so every actor that uses it shares it. For
example, a footstep descriptor with 4 files that last played file 2 and rolls 2 plays file 3, so
no two steps in a row use the same file. The same rule holds for footsteps, swings, and every
other descriptor.

`LNAM` byte 1: `0` no loop, `8` loop, `16` fast envelope, `32` slow envelope. OpenSky keeps
any other value as unknown. It does not guess what it means.

`FNAM` is the older flags word, and shares its value with `LNAM`: the later field wins. Three
bits move to their `LNAM` place: `0x10` is loop, `0x02000000` fast envelope, and `0x04000000`
slow envelope. 63 `Skyrim.esm` descriptors use `FNAM`, with values 0, 1, 2, and `0x11` (a loop).
None has both fields. OpenSky reads the looping from `FNAM` in the same way. Every other bit of
the word, from either field, goes into the flags of each play unchanged. So the low bits
`0x1`, `0x2`, and `0x4` join the output routing bits below.

How the game uses the other fields when the descriptor plays:

- `CTDA` conditions run with the player as subject and target. When they fail, the sound does
  not play.
- `ONAM`, the output model: with its flag bit 0 set, a listener beyond the model's maximum
  attenuation distance, or a model with no attenuation curve, means the sound does not play.
  The model also picks the routing: flag bit 0 with a non-zero second value routes through
  bit 4, flag bit 0 alone through bit 1, and no flag or no model through bit 2. The model's
  attenuation data goes to the player of the sound
  ([output models](/formats/sound-output-reverb.md)).

`LNAM` byte 3 is the rumble send: the low four bits drive one motor and the high four bits the
other, each at the four-bit value times 1 percent of full strength
([SNDR](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SNDR) gives times 7). The Creation
Kit calls it
how much of the sound's level drives each motor
([Sound Descriptor](https://ck.uesp.net/wiki/Sound_Descriptor)). It applies only when the
output model sets Allows Rumble ([output models](/formats/sound-output-reverb.md)).

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
