---
type: Subsystem
title: Perk sky
description: The 3D star field behind the skills menu - the dome, each skill's stars and
  lines, and the camera - and which of its numbers come from the game and which OpenSky picks.
tags: [engine, menus, progression, perks, nif]
---

# Perk sky

Behind the [skills menu](/engine/skills-menu.md) movie the game draws a 3D sky: a dome
of stars and nebulas, the eighteen constellations, and a star for every perk with lines
between them. The movie draws only the text on top. OpenSky draws the sky as a
[menu scene](/rendering/menu-scene.md).

## Meshes

| Mesh | Holds |
| --- | --- |
| `meshes\interface\intperkskydome.nif` | the dome, the constellation art `cImage00` to `cImage17`, the ring anchors `Point00` to `Point17`, and `CameraPosition` |
| `meshes\interface\intperkstars01.nif` | one perk star: a star quad and two glows under a billboard node |
| `meshes\interface\intperkline01.nif` | one line: a beam quad along +Y to the `BeamEnd` node, 56.2 units long |

The install has three more interface meshes that look as if they belong here. The game
does not load them, so OpenSky does not draw them:

| Mesh | Holds | Why it is unused |
| --- | --- | --- |
| `meshes\interface\intstatmenustars.nif` | a separate star field with its own `CameraPosition`, and mage, warrior, and thief art; no sequences | no plugin and no string in `SkyrimSE.exe` names it |
| `meshes\interface\intskillstoperktransitioneffect.nif` | a particle cloud with `FadeIn`, `Loop`, and `FadeOut` | only the art object `INTSkillsToPerkTransitionObject` (`ARTO` 05D47A) names it, and only the visual effect `INTSkillsToPerkTransitionEffect` (`RFCT` 05D47B) names that. No record, no default object, and no form ID in `SkyrimSE.exe` points at the effect |
| `meshes\dlc01\interface\intvampireperkskydome.nif` | the vampire lord's dome | it shows the vampire lord perk tree, which needs the player to transform first |

The skills menu's own paths sit together in the executable's string table:
`Interface/INTPerkSkydome.nif`, `Interface/INTPerkStars01.nif`, and
`Interface/INTPerkLine01.nif`, with `CameraIntro`, `CameraOutro`, `cImage%02i`, and
`Point%02i` nearby. Only names were read, never code.

Observed in the install with `openskycli nif <path> --sequences`:

- The anchors `Point00` to `Point17` sit on a flat ring of radius 99.3 at height -0.07.
  `Point00` is at (0, 99.3); each next point is 20 degrees further clockwise, seen from
  above.
- The constellation art `cImage<n>` sits over `Point<n>`, about 92 units out and 0 to
  35 units up. So a tree grows up (+Z) from its anchor.
- `CameraPosition` is at (0, 0, -3000). Its rotation turns the Gamebryo camera's view
  axis (+X) to +Y, so the camera looks at `Point00` with +Z up.
- `CameraIntro` (0.633 s) moves `CameraPosition` from z = -3000 to z = 0.14, the ring
  centre. `CameraOutro` moves it back. `Idle` (118.7 s, looping) turns the star layers
  slowly and holds `CameraPosition` at -3000.

## Star and line states

The star mesh has a looping sequence per state and a transition into it:

| State | When | Played on entry |
| --- | --- | --- |
| `Locked` | no parent perk is owned | |
| `Unlocked` | the perk has no parent, or a parent is owned | `Unlock` |
| `Owned` | the first rank is owned | `Own` |
| `Selected` | the tree page has this box selected | `Select`; `Deselect` on leaving |

`Unlock` and `Own` carry `SoundPlay` text keys, so a purchase sounds as in the game. A line
is `Unlocked` once its lower perk is owned, else `Locked`.

`intperkline01.nif` also has `LockedFadeIn`, `LockedFadeOut`, `UnlockedFadeIn`, and
`UnlockedFadeOut`. They take the beam's alpha between its state's value and 0.2 over
0.667 s. No string in `SkyrimSE.exe` names them, and the stars have no such fades, so OpenSky
treats them as unused and does not play them.

The scale tracks make an owned star 3.8 times the size of a locked one.

## Layout

A star's place, in the frame of its skill (+X right, +Y out to the anchor, +Z up):

```text
x = (centre - gridX) * fStatsStarXIncrement
y = -(fStatsStarZInitialOffset + gridY * fStatsStarZIncrement * rowScale)
z = gridY * fStatsStarYIncrement * rowScale
```

`gridX` and `gridY` are the `AVIF` grid place plus its offsets (`XNAM` + `HNAM`,
`YNAM` + `VNAM`). `centre` is the middle of the tree's lowest and highest column, so each
tree stands over its anchor. The frame turns by 20 degrees per ring slot, and the star sits
at the slot's anchor plus this offset. A line runs from a perk's star to each star it
connects to.

The `fStatsStar` settings work in a frame that faces the camera: its +X runs to the
left and its +Z toward the camera. So a higher column sits further left, the bottom row
stands 5 units in front of the anchor, and the -9 depth step leans the tree back.

`rowScale` is 0.43. No setting names it. It was measured on four vanilla screenshots of
the tree view on UESP (Archery, Block, Speech, and Smithing, such as
<https://images.uesp.net/9/9d/SR-perktree-Archery.jpg>):

- Archery, Block, and Speech all show a higher column further left, by their line graphs.
  Smithing does not fit any linear layout. Its `AVIF` winner is `Update.esm`, so the
  screenshot most likely shows an older tree.
- Each star was matched to its perk, then projected with OpenSky's tree camera and fitted
  to the screenshot with a scale and a shift. The best fit is a tree that leans back
  with `rowScale` 0.43: about 6 px off on 300 px wide images. A tree that leans forward
  is 19 px off, and a flat one 12 px.
- The fit sees only the ratio of the up step to the across step. The across step of 5
  keeps a tree about as wide as its constellation art.

Every tree is drawn on the ring, not only the open one, as in the game.

## Camera

- On the ring the camera stands at the centre and looks at `fStatsSkillsLookAt`, turned to
  the selected skill. A turn speeds up to `fStatsRotationSpeedMax` over
  `fStatsRotationRampTime` and takes the short way round.
- In a tree it moves, over 0.5 s, to `fStatsStarCameraOffset` and looks at
  `fStatsStarLookAt`.
- On open, the engine calls the movie's `StartCameraAnimation`. The movie then calls
  `MoveCamera` with 0 to 1 as its own timeline plays. OpenSky samples `CameraIntro` at that
  fraction and lifts the camera by `CameraPosition`. Without the movie, a clock gives the
  fraction.
- On close, the movie's text goes at once. The sky then plays `CameraOutro` (0.633 s),
  which drops `CameraPosition` back to z = -3000, and the menu leaves when it ends. Keys
  do nothing during the move.
- The field of view is `fStatsCameraFOV`, used as the vertical angle.

The perk names in the movie's `PerkNamesA` are the stars' places on screen, sent again
each frame the camera moves.

## Where the numbers come from

`Skyrim.esm` stores four of the settings: `fStatsCameraFOV` 50, `fStatsStarXIncrement` 5,
`fStatsStarYIncrement` 15, and `fStatsStarZIncrement` -9. The game binary names the others,
and its built-in defaults are listed on the Creation Kit wiki
(<https://ck.uesp.net/wiki/Category:Settings>). OpenSky reads each setting from the load
order when a plugin sets it. Otherwise it uses the binary's default where its meaning in
OpenSky's frame is known, and its own value where it is not:

| Setting | Binary default | OpenSky value | Why |
| --- | --- | --- | --- |
| `fStatsStarScale` | 0.15 | 0.15 | the binary's default |
| `fStatsLineScale` | 0.1175 | 0.1175 | the binary's default |
| `fStatsStarZInitialOffset` | 5 | 5 | the binary's default; the screenshot fit is better with it |
| `fStatsCameraNearDistance` | 1 | 1 | the menu scene's near plane |
| `fStatsRotationSpeedMax` | 0.5 | 180 degrees per second | the unit of 0.5 is not known; one slot turns in about 0.2 s |
| `fStatsRotationRampTime` | 2000 | 0.25 s | 2000 is most likely milliseconds, but the speed it ramps to is not known |
| `fStatsSkillsLookAt` | (0, 0, 5) | (0, 100, 10) | the binary's vectors are relative to a point that is not known |
| `fStatsStarCameraOffset` | (0, -8, 0) | (0, 45, 12) | a full tree fills the screen height |
| `fStatsStarLookAt` | (0, 0, 1) | (0, 95, 15) | |

The CK wiki marks that page as incomplete, so the defaults are a community dump, not a
specification.

## Where OpenSky differs

- The ring camera, the tree camera, and the turn speed use OpenSky's values, as the table
  above says.
