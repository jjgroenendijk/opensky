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
on the player, so the save carries it. Closing the menu rebuilds the player's body and
queues `OnRaceSwitchComplete` on the player's scripts.

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
([TRI](/formats/tri.md)) by its sign, with the absolute value as the weight. The order and
the sign of each pair come from the xEdit and UESP field lists for `NPC_ NAM9`:

| Index | Negative | Positive |
| --- | --- | --- |
| 0 | `NoseShort` | `NoseLong` |
| 1 | `NoseDown` | `NoseUp` |
| 2 | `JawDown` | `JawUp` |
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
| 15 | `ChinMoveDown` | `ChinMoveUp` |
| 16 | `Overbite` | `Underbite` |
| 17 | `EyesBack` | `EyesForward` |
| 18 | | `VampireMorph` |

[WARNING] The target names were read from the installed chargen TRI. The pairing to
`NAM9` indices and the sign of each pair are not yet checked against a baked FaceGen head.
A `NAMA` value `n` above 0 selects the target `NoseType<n>`, `EyesType<n>`, or `LipType<n>`;
whether 0 means "no target" is also unverified.

Body weight blends the thin `_0` and heavy `_1` meshes linearly. Tint layers paint over the
face color map in record order, each as a straight alpha blend of its mask, color, and
strength (`TINV` divided by 100).

## Not done yet

- The vanilla `racesex_menu.swf` movie is not driven. Its callbacks were measured with
  `openskycli swf movie-probe`; the rows are OpenSky's own.
- The player head is not rebuilt from chargen TRI deltas and painted tints in the scene.
  The morph and tint math exists and is tested; the scene still uses the record's head.
