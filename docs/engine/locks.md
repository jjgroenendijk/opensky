---
type: Subsystem
title: Locks and lockpicking
description: How XLOC lock data gates the use key, how keys and Papyrus change a lock, the
  lockpicking model with its sources, and the 2D lockpicking menu.
tags: [engine, interaction, inventory, progression]
---

# Locks and lockpicking

A door or container can carry `XLOC` lock data: a level, an optional `KEYM` key, and flags.
OpenSky keeps the plugin value as the baseline and stores a change as a runtime component, so a
picked lock stays open and a save remembers it.

Sources: UESP "Skyrim:Lockpicking" for the formulas, UESP "Skyrim Mod:Mod File Format/REFR"
for `XLOC`, and the install's GMSTs for every number a setting names. The `XLOC` layout is on
[placed references](/formats/placed-references.md).

## Levels

| `XLOC` level | Band | GMST suffix | Name |
| --- | --- | --- | --- |
| 0 or 1 | Novice | `VeryEasy` | Novice |
| 25 | Apprentice | `Easy` | Apprentice |
| 50 | Adept | `Average` | Adept |
| 75 | Expert | `Hard` | Expert |
| 100 | Master | `VeryHard` | Master |
| 255 | Requires key | `Impossible` | Requires Key |

`iLockLevelMaxVeryEasy` (1) bounds Novice. A value between two rows falls in the higher band,
so Papyrus `SetLockLevel(30)` is Adept. The names are English: the install's
`sLockLevelName*` settings are lstrings, and the string tables are not read for them.

[WARNING] Flag 0x04 marks a leveled lock. No open source says how the game scales it, so
OpenSky uses the authored level.

## The use-key gate

Every press of the use key goes through one gate before any listener hears it
([interaction](/engine/interaction.md)):

1. No lock, or unlocked: the press goes on.
2. Locked, and the player carries the key: the lock opens, it stays open, and the press goes on.
3. Locked otherwise: the press is refused. Audio, scripts, and the inventory never hear it.

A refused pickable lock opens the lockpicking menu when the player has at least one lockpick
(the `LKPK` default object). When the lock opens, the original press runs again, so the door
opens or the container menu appears.

## Papyrus

`ObjectReference` natives read and write the same state as the gate:

| Native | Effect |
| --- | --- |
| `Lock(abLock = true, abAsOwner = false)` | Locks or unlocks. A reference with no `XLOC` gets level 1, an OpenSky choice |
| `SetLockLevel(aiLevel)` | Sets the level, clamped to 0 to 255. The locked flag stays |
| `IsLocked()` | False for a reference with no lock |
| `GetLockLevel()` | 0 for a reference with no lock |
| `GetKey()` | The key, when it is a resident reference; otherwise None |

`abAsOwner` is ignored: crime does not watch locks.

## Lockpicking model

The pick moves along a 180 degree arc, 90 degrees either side of upright. A hidden sweet spot
sits somewhere on the arc. Turning the lock with the pick in the sweet spot opens it. In a
partial zone beside the sweet spot, the lock turns part of the way and then strains the pick.
Outside, the lock does not turn at all and the pick strains at once.

With `L` the Lockpicking skill, clamped to 0 to 100:

| Quantity | Formula | Source |
| --- | --- | --- |
| Sweet-spot width | `fSweetSpot<band> * (0.82 + fLockpickSkillSweetSpotMult * L) * perk` | UESP; 0.82 has no GMST |
| Partial-zone width | `fPartialPick<band> * (fLockpickSkillPartialPickBase + fLockpickSkillPartialPickMult * L)` | UESP and GMSTs |
| Pick life while straining | 2, 1, 0.75, 0.5, 0.25 seconds, times `1 + 0.5 * L / 100` | UESP; no GMST |

Install values: `fSweetSpot*` 30, 15, 7.5, 3.75, 1.875; `fPartialPick*` 22, 18, 14, 10, 6;
`fLockpickSkillSweetSpotMult` 0.006; `fLockpickSkillPartialPickBase` 0.775 and `...Mult`
0.015. A broken pick leaves the inventory, and pick health carries over between locks, as UESP
says.

The turn speed (1.5 turns per second) and the return speed (3) are OpenSky's own. The
lockpicking session is a pure value: the sweet spot is drawn from a seeded generator by the
coordinator, so a test can replay a session.

## Perks

| Entry point | Index | Vanilla perk | Effect |
| --- | --- | --- | --- |
| Mod Lockpick Sweet Spot | 59 | `NoviceLocks00` to `MasterLocks100` | Multiplies the width, under `GetLockLevel` conditions |
| Set Lockpick Starting Arc | 63 | `Locksmith` (45) | A fresh pick starts within half of this many degrees of the sweet spot |
| Make Lockpicks Unbreakable | 65 | `Unbreakable` (1) | Picks never break |
| Mod Lockpicking Key Reward Chance | 90 | `WaxKey` (100) | Percent chance to receive the key on success |

The perk runtime binds the lock as the locked reference, and the condition function
`GetLockLevel` (65) answers with its level. "Locksmith starts near the sweet spot" is OpenSky's
reading of the entry point name.

## Skill use

An opened lock reports `fSkillUsageLockPick<band>` uses (2, 3, 5, 8, 13). A broken pick reports
`fSkillUsageLockPickBroken` (0.25). See [skill advancement](/engine/skill-advancement.md).

## The menu

The game draws a 3D lock from a NIF. OpenSky draws a 2D overlay with the immediate-mode UI
layer instead: the arc as dots, the pick, the keyhole turning with the lock, a turn bar, a pick
health bar, the pick count, and the difficulty. The world pauses under it.

| Input | Action |
| --- | --- |
| Mouse, A and D, left and right arrows | Move the pick |
| W or up arrow, held | Turn the lock |
| Escape | Leave |

These bindings are OpenSky's. The sounds are the install's `SNDR` records, found by editor ID:
`UILockpickingEnter`, `UILockpickingCylinderTurn`, `UILockpickingCylinderStop`,
`UILockpickingPickBreak`, and `UILockpickingUnlock`.

## Saves

The `LOCK` chunk holds every changed lock ([save format](/formats/opensky-save.md)).

## Checking it in the app

World > Inventory & Equipment > Locks lists the locks in the loaded cells. The selected lock
gets a yellow marker in the world. The section can unlock and relock it, open the lockpicking
menu on it, and let the player carry every key. The readout shows the last session: whether
the lock opened, the picks broken, and the experience given. The record views in the Asset
Browser show a reference's `XLOC` level and key.
