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
| `meshes\interface\intskillstoperktransitioneffect.nif` | a particle cloud for the move into a tree; OpenSky does not draw it yet |

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

The scale tracks make an owned star 3.8 times the size of a locked one.

## Layout

A star's place, in the frame of its skill (+X right, +Y out to the anchor, +Z up):

```text
x = (gridX - 2) * fStatsStarXIncrement
y = fStatsStarZInitialOffset + gridY * fStatsStarZIncrement * rowScale
z = gridY * fStatsStarYIncrement * rowScale
```

`gridX` and `gridY` are the `AVIF` grid place plus its offsets (`XNAM` + `HNAM`,
`YNAM` + `VNAM`). The frame turns by 20 degrees per ring slot, and the star sits at the
slot's anchor plus this offset. A line runs from a perk's star to each star it connects to.

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
- The field of view is `fStatsCameraFOV`, used as the vertical angle.

The perk names in the movie's `PerkNamesA` are the stars' places on screen, sent again
each frame the camera moves.

## Where the numbers come from

`Skyrim.esm` stores four of the settings: `fStatsCameraFOV` 50, `fStatsStarXIncrement` 5,
`fStatsStarYIncrement` 15, and `fStatsStarZIncrement` -9. The game binary names the others
(`fStatsCameraNearDistance`, `fStatsLineScale`, `fStatsRotationRampTime`,
`fStatsRotationSpeedMax`, `fStatsSkillsLookAt[XYZ]`, `fStatsStarCameraOffset[XYZ]`,
`fStatsStarLookAt[XYZ]`, `fStatsStarScale`, `fStatsStarZInitialOffset`), but their values
are not in any plugin. OpenSky reads each one from the load order when a plugin sets it,
and otherwise uses its own value:

| Setting | OpenSky value | Chosen so that |
| --- | --- | --- |
| `fStatsStarScale` | 0.15 | a locked star is about 1.7 units wide |
| `fStatsLineScale` | 0.15 | a beam is about as wide as a locked star |
| `fStatsRotationSpeedMax` | 180 | one slot turns in about 0.2 s |
| `fStatsRotationRampTime` | 0.25 | |
| `fStatsSkillsLookAt` | (0, 100, 10) | the art sits above the movie's skill names |
| `fStatsStarCameraOffset` | (0, 45, 12) | a full tree fills the screen height |
| `fStatsStarLookAt` | (0, 95, 15) | |
| `fStatsStarZInitialOffset` | 0 | |

[WARNING] The three increments as stored make a six-row tree about 90 units tall, while
the constellation art is about 35 units tall. OpenSky multiplies the up and depth steps by
its own `rowScale` of 0.4, so the trees fit their art. The game likely scales them some
other way that is not yet known. The across step (5) fits the art without a factor.

## Where OpenSky differs

- The particle cloud of `intskillstoperktransitioneffect.nif` is not drawn on the move into a
  tree.
- The menu closes at once; the game plays `CameraOutro` first.
- The settings in the table above are OpenSky's guesses.
