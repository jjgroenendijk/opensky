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
- Some presets have no skin tone layer (`TINP` 6), such as Redguard male, Dark Elf, and the
  female Nord and Breton, and no Khajiit or Argonian preset has one. Such a face takes the
  mask's `TIND` colour at the `TINV` of that colour's `TINC` entry. Every playable race
  lists its `TIND` colour among its `TINC` entries. The Creation Kit bakes faces the same
  way: `Hulda` has no skin tone layer, and her baked face tint (mean 213, 208, 209) matches
  the Nord female default (221, 221, 221). The Creation Kit wiki page "Tutorial Creating a
  Playable Race" describes the default and its blend value
  (<https://ck.uesp.net/wiki/Tutorial_Creating_a_Playable_Race>).
- A control the race offers nothing for is left out, so its slider does not show.
- The 19th `NAM9` value is the vampire morph; the menu does not show it.

The type ranges come from the chargen TRI of the race and sex's default face part. The world
load reads each TRI once and keeps its highest `NoseType`, `EyesType`, and `LipType` target.
Type 0 is the base shape. Measured on the install:

| Chargen TRI | Nose | Eyes | Lips |
| --- | --- | --- | --- |
| Human and elf male | 0 to 30 | 0 to 37 | 0 to 30 |
| Human and elf female (`FemaleHeadCharGen.tri`) | 0 to 30 | 0 to 28 | 0 to 30 |
| Khajiit and Argonian | 0 to 5 | 0 to 5 | 0 to 4 or 5 |

A TRI that cannot be read falls back to the female human ranges.

The game settings `iNoseMorphCount` (31), `iEyeMorphCount` (38), and `iLipMorphCount` (31)
count the types with type 0 included. They can only narrow a range, so a plugin that lowers a
count shortens its row. `iBrowMorphCount` (20) has no TRI targets to check, because brows are
head parts.

The real-data suite `FaceMorphCountRealDataTests` (`make test-real ALL=1`) checks every playable
race's chargen TRI against the counts and writes each difference to `.logs/face-morph-counts/`.
No TRI holds more types than its count allows. Each race's `MPAV` fields (UESP "Skyrim
Mod:Mod File Format/RACE", <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/RACE>) set every
bit of their first two flag words in vanilla, so they do not limit the types.

[WARNING] The vanilla Head category also has an Age control (`sRSMAge`). No record names what it
changes, so OpenSky leaves it out. A lead: each race's `FTSM`/`FTSF` list mixes complexion
texture sets with age ones, such as `SkinHeadMaleNordComplexion_Age40` and
`SkinHeadMaleKhajiitOld`. The movie's own test list sends only one `ChangeFaceDetails` slider.

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

Body weight blends the thin `_0` and heavy `_1` meshes linearly. Tint layers paint in record
order into a face tint picture, each as a straight blend of its mask, color, and strength
(`TINV` divided by 100). The fourth `TINC` byte is 0 in every vanilla NPC seen, for example
the `Player` record and `Hulda`, so it is not used as alpha.

A real-data probe rebuilt the face tint of six vanilla NPCs this way (`Ralof`, `Hadvar`,
`Ysolda`, `Belethor`, `Nazeem`, `Faendal`) and compared it with their baked
`facegendata\facetint` texture. The mean error was 1.5 to 2.8 out of 255 per channel. Their
skin tone layer covers the whole face at full strength, so the start colour does not matter
for them. NPCs with a weak skin tone layer show the start: from grey 127 the mean error is
1.4 to 2.9, and from white it is 28 to 129. Examples are `CWBattleGalmar` (strength 0),
`POIMageIlasTei` (32), `DA11Sanyon` (66), and `Jdatharr` (74). So the layers paint over grey
127, the neutral grey of the overlay blend.

## The drawn head

Once the player has an identity, the head is assembled from its parts instead of the baked
FaceGen head, because the baked head belongs to the record's race and face.

- Each head part whose `HDPT` names a chargen TRI (`NAM0` 2) gets one morph buffer per
  skinned mesh, set to the slider weights. The buffer is the one expressions use, so the
  vertex shader adds the deltas before skinning. A TRI whose vertex count differs from the
  mesh is skipped and logged.
- The tint masks are decoded on the CPU ([DDS](/formats/dds.md), "CPU decode") and painted
  into a face tint picture at the first mask's size. It uploads under a texture key named
  after the layers, so the same face reuses one upload. The face part keeps its color map and
  overlays the face tint, the same way an NPC's baked face overlays its `facetint` texture.
  Painting the layers straight over the color map instead makes the face the flat skin
  tone colour, much paler than the body.
- The body keeps the race skin texture. The skin tone layer (`TINP` 6) paints the face, and
  it also gives the body's skin tone, which an NPC stores as `QNAM`:
  `QNAM` × 255 = 127 + (colour − 127) × strength. This fits all 2168 NPCs in `Skyrim.esm`
  that have a skin tone layer, within 1.6 of 255: 1959 at strength 100, where `QNAM` is
  the colour, and 209 below it. For example, `KhajiitMalePreset10` has black at 50 and
  stores 63. 127 is the neutral grey of the skin shader's overlay blend, so a layer at
  strength 0 leaves the body texture as it is.
- Each head part's texture set adds its detail map (`TX04`), which the lit shader already
  reads for FaceGen faces. The player's complexion, or an NPC's `FTST`, replaces the face
  part's texture set.

## The race menu movie

Its calls were measured with `openskycli swf movie-probe`.

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

The engine calls these back:

| Callback | When |
| --- | --- |
| `HideLoadingIcon` | After each change is applied. Before it sends a change, the movie shows `LoadingIconInstance` and waits for the engine; without this call the icon stays |

Each `Set...List` call clears its list with `entryList.splice(0, entryList.length)` before
it fills it, so sending the lists again leaves one copy of each row.

A race, sex, preset, or war paint change moves other controls, so the engine sends the sliders
again.

The interface translation file has `$RACE` but no `$BODY` or `$HEAD`, and the movie only uses
`$RACE` as placeholder text, so the names must arrive as plain text. The movie does not change
their case.

`SetPlatform` makes each `CrossPlatformButtons` clip attach its key art. Without it, the buttons
show the placeholder text `TEXT`. An empty race description makes the movie print
"No race description for" and the race name.

The movie's Done button calls `ConfirmDone` only on a mouse click; its key handler does not
look at the Done key. So the engine reads that key itself. The button's art is the `XButton`
user event. The install's `controlmap.txt` binds `XButton` in its "Item Menus" context to the
Ready Weapon key, `R` on PC ([control map](/formats/controlmap.md)). That key closes the
menu, as `ConfirmDone` does.

On PC the categories change only with a click on the arrows beside the category name. The
movie's key handler moves between categories only on a gamepad, with the triggers. The arrow keys,
`W`, and `S` move inside the open list, and `Tab` moves focus to the second list. While the race
menu or the title menu is open, the engine frees the mouse cursor so a click reaches the movie.

Before it sends the lists, the engine checks that the movie built its category list. When it did
not, the movie closes and the engine rows stay in charge.

## The camera

While the race menu is open, the view looks at the player's face from in front, at eye height,
and the player's body is drawn even in first person. It uses the
[dialogue camera](/engine/dialogue-camera.md) framing, taken from the side the player faces.
[WARNING] The game's race menu camera is not documented, and `Skyrim.esm` has no setting for it,
so this framing is OpenSky's choice.

## Not done yet

- The Age control, above.
