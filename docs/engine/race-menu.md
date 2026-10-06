---
type: Subsystem
title: Race menu
description: The race menu rows, the limited mode scripts open, how a chosen face becomes
  chargen morph weights, and what is not verified.
tags: [engine, ui, menu, actors, face]
---

# Race menu

The race menu edits the player's identity: race, sex, name, body weight, the face sliders,
and the nose, eye, and mouth types. The result is a `playerIdentity` world-state component
on the player, so the save carries it. Each step of a row stores the identity at once, so
the drawn head follows the slider. Closing the menu queues `OnRaceSwitchComplete` on the
player's scripts.

## Rows

| Row | Range |
| --- | --- |
| Race | The `RACE` records with the playable flag |
| Sex | Male or female |
| Weight | 0 to 100, `NPC_ NAM7` |
| 18 face sliders | -1 to 1 in steps of 0.1, `NPC_ NAM9` |
| Nose, eye, mouth type | `NPC_ NAMA` groups 0, 2, and 3 |
| Name | Up to 64 characters |

The type ranges come from the chargen TRI of the female head: 30 nose targets, 28 eye
targets, and 30 lip targets. The 19th `NAM9` value is the vampire morph; the menu does not
show it.

## Limited mode

`Game.ShowLimitedRaceMenu` hides the name and sex rows, and the race row disappears once
the player leaves it. Source: the Creation Kit wiki page "ShowLimitedRaceMenu".

## Chargen morphs

Each `NAM9` slider picks one of two targets of the head part's chargen TRI
([TRI](/formats/tri.md)) by its sign, with the absolute value as the weight. The order
starts from the xEdit and UESP field lists for `NPC_ NAM9`. A real-data probe then checked
it against baked FaceGen heads (below):

| Index | Negative | Positive |
| --- | --- | --- |
| 0 | `NoseShort` | `NoseLong` |
| 1 | `NoseDown` | `NoseUp` |
| 2 | `JawUp` | `JawDown` |
| 3 | `JawNarrow` | `JawWide` |
| 4 | `JawBack` | `JawForward` |
| 5 | `CheeksDown` | `CheeksUp` |
| 6 | `CheeksIn` | `CheeksOut` |
| 7 | `EyesMoveDown` | `EyesMoveUp` |
| 8 | `EyesMoveIn` | `EyesMoveOut` |
| 9 | `BrowDown` | `BrowUp` |
| 10 | `BrowIn` | `BrowOut` |
| 11 | `BrowBack` | `BrowForward` |
| 12 | `LipMoveDown` | `LipMoveUp` |
| 13 | `LipMoveIn` | `LipMoveOut` |
| 14 | `ChinThin` | `ChinWide` |
| 15 | `ChinMoveUp` | `ChinMoveDown` |
| 16 | `Overbite` | `Underbite` |
| 17 | `EyesBack` | `EyesForward` |
| 18 | | `VampireMorph` |

A `NAMA` value `n` selects the target `NoseType<n>` (field 0), `EyesType<n>` (field 2), or
`LipType<n>` (field 3). Field 1 is -1 or 0 and selects nothing. The TRI has no `Type0`
targets, so 0 in the other fields means the base shape, and -1 means none.

The probe (`ChargenMorphOrderRealDataTests`, run with `make test-real`) builds the face of
29 vanilla NPCs from `NAM9` and `NAMA` and compares it with the face shape in their baked
FaceGen mesh. For each slider it measures the error again with the sign flipped and with the
slider left out. Results are in `.logs/chargen-morph-order/fit.txt`:

- The built face is closer than the TRI base for every NPC, for example `Hulda` 0.128
  against 0.273 (root mean square distance in game units).
- Flipping makes the fit worse for all 18 sliders. Indices 2 and 15 needed the pair the
  other way round from the field lists, so the table above has `JawDown` and `ChinMoveDown`
  on the positive side.
- Index 11 (`BrowForward`) has the right sign but fits slightly better left out, so its
  weight scale is not confirmed.
- [WARNING] `NAM9` index 18 is `3.40282e+38` (the largest float) in most NPCs and 0 in some.
  OpenSky applies `VampireMorph` at weight 1 for any value above 0. The baked faces fit a
  little better with it at weight 1 even where the value is 0, so what the value means is
  not known.

Body weight blends the thin `_0` and heavy `_1` meshes linearly. Tint layers paint over the
face color map in record order, each as a straight blend of its mask, color, and strength
(`TINV` divided by 100). The fourth `TINC` byte is 0 in every vanilla NPC seen, for example
the `Player` record and `Hulda`, so it is not used as alpha.

## The drawn head

Once the player has an identity, the head is assembled from its parts instead of the baked
FaceGen head, because the baked head belongs to the record's race and face.

- Each head part whose `HDPT` names a chargen TRI (`NAM0` 2) gets one morph buffer per
  skinned mesh, set to the slider weights. The buffer is the one expressions use, so the
  vertex shader adds the deltas before skinning. A TRI whose vertex count differs from the
  mesh is skipped and logged.
- The face part's color map is decoded on the CPU, the tint masks are scaled to its size,
  and the layers are painted over it ([DDS](/formats/dds.md), "CPU decode"). The result
  uploads under a texture key named after its inputs, so the same face reuses one upload.
- The body keeps the race skin texture. The skin tone layer paints the face only.

## The race menu movie

The panel's Movie toggle shows `interface\racesex_menu.swf` over the world. Its calls were
measured with `openskycli swf movie-probe`.

| Engine calls | Values |
| --- | --- |
| `SetCategoriesList` | Race, body, and head pages, with flags 1, 2, and 4 |
| `SetRaceList` | Per race: name, description, and 1 for the current race |
| `SetSliders` | Per slider: 8 values, the name, page flag, callback, minimum, maximum, value, step, and id |
| `SetNameText` | The character's name |

| Movie calls | Effect |
| --- | --- |
| `ChangeRace` | Picks a race by its place in the list, then sends the lists again |
| A slider callback, such as `ChangeDoubleMorph` | Sets that slider's row, clamped to its range |
| `ChangeName` | Sets the name |
| `ConfirmDone` | Closes the menu |

Each change goes through the same model as the panel rows, so the head updates the same way.
Sound and camera calls are accepted and ignored.

## Not done yet

- The `racesex_menu.swf` movie shows OpenSky's own rows. The movie's camera, zoom, and
  preset buttons are not answered.
