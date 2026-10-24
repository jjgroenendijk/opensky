---
type: File Format
title: Animation data text files
description: The two meshes\animationdata text files per behavior project - the clip list
  with speed, crop, and triggers, and the root motion table - and how they were read.
tags: [format, animation, behavior]
---

# Animation data text files

Havok clips in Skyrim carry no root motion of their own: the root bone stays at the clip
origin. The motion that moves an actor, such as a chair exit stepping it aside, lives in two
plain text files per behavior project, under `meshes\animationdata\` in
`Skyrim - Animations.bsa`. OpenSky reads them to move an actor into and out of furniture
([furniture](/engine/furniture.md)).

No spec page covers these files: the UESP and Creation Kit mirrors have none. The layout
below was read from the install's own files. Lines end in `\r\n`. Numbers are decimal text.

## Project names

A project is named after the project file in the actor's folder, without `.hkx`:
`meshes\actors\character\defaultmale.hkx` gives `defaultmale`, and
`meshes\actors\bear\bearproject.hkx` gives `bearproject`. One folder can hold two projects
(`canine` has `dogproject` and `wolfproject`), so OpenSky tries each project of the folder
and takes the first that knows the clip.

## Clip list: `<project>.txt`

| Lines | Meaning |
| --- | --- |
| 1 | A number, always `1` in the vanilla files |
| 1 | `n`, the count of behavior files |
| `n` | The project's behavior and character files, such as `Behaviors\0_Master.hkx` |
| 1 | `1` when clip blocks follow, `0` when the project has none |
| rest | Clip blocks, each followed by a blank line |

A clip block:

| Line | Meaning | `Chair_LeftExit` |
| --- | --- | --- |
| 1 | The clip generator's name, as `hkbClipGenerator` `m_name` spells it | `Chair_LeftExit` |
| 2 | The motion index into the motion table | `479` |
| 3 | Playback speed | `1` |
| 4 | Crop start | `0` |
| 5 | Crop end | `0` |
| 6 | `t`, the trigger count | `2` |
| `t` | One trigger per line, `name:seconds` | `SoundPlay:0.0333333`, `IdleFurnitureExit:1.3` |

## Motion table: `boundanims\anims_<project>.txt`

Blocks, each followed by a blank line:

| Lines | Meaning |
| --- | --- |
| 1 | The motion index |
| 1 | The clip duration in seconds |
| 1 | `a`, the translation key count |
| `a` | `time x y z`: the root's offset at `time`, in the frame the clip starts in |
| 1 | `b`, the rotation key count |
| `b` | `time x y z w`: the root's turn at `time`, a quaternion |

Before the first key the actor has not moved, so OpenSky adds a key of no motion at time 0
and interpolates between keys: linearly for the offset, by slerp for the turn. In the
start frame `+y` is forward and `+x` is right, and a positive z quaternion turns left.
One index can appear in more than one block; OpenSky keeps the first.

## Confirmed on the install

- `defaultmale.txt` holds 2,135 clip blocks and every one parses.
  `anims_defaultmale.txt` holds 1,279 distinct indices, with at most 28 translation keys and
  38 rotation keys in a block.
- `Chair_LeftEnter` (index 478): 1.77 s, ends at `(0, 52.088, 0)` turned 90 degrees left.
  An actor that starts 52 units left of the seat facing it walks forward and turns onto it.
- `Chair_LeftExit` (479) ends at `(-52.088, 0, 0)` turned 90 degrees left;
  `Chair_RightExit` (481) at `(52.088, 0, 0)` turned 90 degrees right. The two mirror each
  other, which fits left being `-x`.
- `Chair_FrontExit` (470) ends at `(-1.07, 47.65, 0)`: forward, out of the chair.
