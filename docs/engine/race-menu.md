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

## Controls

The menu has the vanilla seven categories, each a filter flag on its controls: Race 1,
Body 2, Head 4, Face 8, Eyes 16, Brow 32, and Mouth 64. Each control's label is an `sRSM`
game setting, so it follows the game's language. The order was read from the movie's own
test list (`racesex_menu.swf`, `FaceChanges`), which names the callbacks the game uses.

| Category | Controls, in order | Data |
| --- | --- | --- |
| Body | Sex, Skin Tone, Weight | Tint type 6; `NPC_ NAM7` 0 to 100 |
| Head | Presets, Hair, Hair Color, Beard, Scars, Complexion, Dirt, Dirt Color, War Paint, War Paint Color, Laugh Lines, Forehead, Neck | `RPRM`/`RPRF`; `HDPT` hair, facial hair, scar; `AHCM`/`AHCF`; `FTSM`/`FTSF`; tint types 14, 7, 8, 13, 12 |
| Face | Nose Type, Nose Height, Nose Length, Nose Color, Jaw Width, Height, Forward, Cheekbone Height, Width, Cheek Color, Lower Cheek Color, Chin Width, Length, Forward, Chin Color | `NAMA` 0; `NAM9` 1, 0, 3, 2, 4, 5, 6, 14, 15, 16; tint types 10, 2, 9, 11 |
| Eyes | Eye Shape, Eye Color, Eye Height, Width, Depth, Eyeliner, Socket Upper, Socket Lower | `NAMA` 2; `HDPT` eyes; `NAM9` 7, 8, 17; tint types 3, 4, 5 |
| Brow | Brow Type, Height, Width, Forward | `HDPT` eyebrows; `NAM9` 9, 10, 11 |
| Mouth | Mouth Type, Mouth Height, Forward, Lip Color | `NAMA` 3; `NAM9` 12, 13; tint type 1 |

- A head part control lists the playable `HDPT` records of that type whose sex flag fits
  and whose valid-race `FLST` holds the race. Beard and scars start with "none".
- A colour control picks one of the mask's `TINC` colours, painted at its `TINV` value.
  Some records store `TINV` as a percent, so a value over 1 is divided by 100.
- War paint and dirt pick one mask of their type, or none, and then a colour for it.
- Complexion picks one of the race's `FTSM`/`FTSF` face texture sets, or the race default
  (`DFTM`/`DFTF`). It replaces the face part's diffuse, normal, and detail maps.
- A race or sex change brings that race's choices, and the face takes its first preset, so
  no part of the old race stays. A preset keeps the weight.
- A control the race offers nothing for is left out, so its slider does not show.
- The 19th `NAM9` value is the vampire morph; the menu does not show it.

The type ranges come from the chargen TRI of the female head: 30 nose targets, 28 eye
targets, and 30 lip targets.

[WARNING] The vanilla Head category also has an Age control (`sRSMAge`). No record names what it
changes, so OpenSky leaves it out.

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
- The body keeps the race skin texture. The skin tone layer (`TINP` 6) paints the face, and
  its colour becomes the body's skin tone, which an NPC stores as `QNAM`. Ralof's layer
  colour divided by 255 equals his `QNAM`. The layer strength is not used for the body; for
  vanilla NPCs it is 100, so its role there is not known.
- Each head part's texture set adds its detail map (`TX04`), which the lit shader already
  reads for FaceGen faces. The player's complexion, or an NPC's `FTST`, replaces the face
  part's texture set.

## The race menu movie

The panel's Movie toggle shows `interface\racesex_menu.swf` over the world. Its calls were
measured with `openskycli swf movie-probe`.

| Engine calls | Values |
| --- | --- |
| `SetPlatform`, `InitExtensions` | On the root, at start. The root forwards both to the panels |
| `SetCategoriesList` | The seven categories, each a name and its flag |
| `SetRaceList` | Per race: name, `RACE` `DESC`, and 1 for the current race |
| `SetOptionSliders` | Per slider: 8 values, the name, page flag, callback, minimum, maximum, value, step, and id |
| `SetNameText` | The character's name |

| Movie calls | Effect |
| --- | --- |
| `ChangeRace` | Picks a race by its place in the list, then sends the lists again |
| A slider callback | Sets that control, clamped to its range. `ChangeWeight`, `ChangeDoubleMorph` (sliders), `ChangePreset` (`NAMA` types), `ChangeHeadPreset`, `ChangeHeadPart`, `ChangeHairColorPreset`, `ChangeFaceDetails` (complexion), `ChangeTintingMask`, and `ChangeSex` |
| `ZoomPC` | `true` frames the face, `false` the whole body |
| `PlaySound` | Plays the named `SNDR` descriptor, as every menu does |
| `ChangeName` | Sets the name |
| `ConfirmDone` | Closes the menu |

Each change goes through the same model as the panel rows, so the head updates the same way.
A race, sex, preset, or war paint change moves other controls, so the engine sends the
sliders again.

The interface translation file has `$RACE` but no `$BODY` or `$HEAD`, and the movie only uses
`$RACE` as placeholder text, so the names must arrive as plain text. The movie does not change
their case.

`SetPlatform` makes each `CrossPlatformButtons` clip attach its key art. Without it, the buttons
show the placeholder text `TEXT`. An empty race description makes the movie print
"No race description for" and the race name.

The movie's Done button calls `ConfirmDone` only on a mouse click; its key handler does not
look at the Done key. So the engine reads that key itself. The button's art is the `XButton`
user event. The install's `controlmap.txt` binds `XButton` in menus to the Ready Weapon key,
`R` on PC. That key closes the menu, as `ConfirmDone` does.

Before it sends the lists, the engine checks that the movie built its category list. When
it did not, the movie closes and the engine rows stay in charge. The sidebar race menu panel
shows those rows, and the arrow keys move them.

## The camera

While the race menu is open, the view looks at the player's face from in front, at eye height,
and the player's body is drawn even in first person. It uses the
[dialogue camera](/engine/dialogue-camera.md) framing, taken from the side the player faces.
[WARNING] The game's race menu camera is not documented, and `Skyrim.esm` has no setting for it,
so this framing is OpenSky's choice.

## Not done yet

- The Age control, above.
