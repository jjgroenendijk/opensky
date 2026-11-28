---
type: Subsystem
title: Locks and lockpicking
description: How XLOC lock data gates the use key, how keys and Papyrus change a lock, how a
  leveled lock scales, the lockpicking model with its sources, and the 3D lockpicking menu.
tags: [engine, interaction, inventory, progression]
---

# Locks and lockpicking

A door or container can carry `XLOC` lock data: a level, an optional `KEYM` key, and flags.
OpenSky keeps the plugin value as the baseline and stores a change as a runtime component, so a
picked lock stays open and a save remembers it.

Sources: UESP "Skyrim:Lockpicking" for the formulas, UESP "Skyrim Mod:Mod File Format/REFR"
for `XLOC`, and the install's GMSTs for every number a setting names. The `XLOC` layout is on
[placed references](../formats/placed-references.md).

## Levels

| `XLOC` level | Band | GMST suffix | Name |
| --- | --- | --- | --- |
| 0 or 1 | Novice | `VeryEasy` | Novice |
| 25 | Apprentice | `Easy` | Apprentice |
| 50 | Adept | `Average` | Adept |
| 75 | Expert | `Hard` | Expert |
| 100 | Master | `VeryHard` | Master |
| 255 | Requires key | `Impossible` | Requires Key |

`iLockLevelMaxVeryEasy` (1) bounds Novice; a plugin that raises it widens Novice. A value
between two rows falls in the higher band, so Papyrus `SetLockLevel(30)` is Adept. The names
come from the `sLockLevelName*` string settings, and the prompt verb from `sUnlock`. Without
string tables the English names above stay.

## Leveled locks

`XLOC` flag 0x04 marks a leveled lock. The game works out its level as:

level = authored level + L × truncate(`fLeveledLockMult`), at most 99.

- `fLeveledLockMult` is 1.5, which truncates to 1.
- L is the level of the reference's encounter zone. With no zone, or the default zone, L is the
  player's level.
- A level of 255 (requires key) does not scale.
- The bands then apply as in the table above.

Example: an authored level of 25 in a zone of level 30 gives 55, which is Expert. Viola
Giordano's front door in Windhelm is a leveled Adept lock (50). At player level 1 it is 51,
Expert, and from level 26 it is 76 or more, Master. UESP "Skyrim:That Was Always There" calls
it "a difficult leveled lock (Expert or Master level)".

The stored level stays the authored one, so a picked and relocked lock keeps scaling. A save
holds the authored level too: `openskycli ess locks <save.ess>` lists each `ExtraLock` beside
the plugin's `XLOC`, and every leveled lock in 13 saves, at player levels 1 to 17, stored its
authored level. The vanilla masters hold 146 leveled locks: 142 in `Skyrim.esm` and 4 in
`Dragonborn.esm`. Most are Thieves Guild strongboxes (`TGRStrongbox`), jail evidence chests,
and city doors.

[WARNING] OpenSky does not follow this rule yet. It raises the lock one band for every 10
player levels above level 1, stops at Master, and does not read the encounter zone. Papyrus
`SetLockLevel` to another level stops the scaling, and `GetLockLevel` answers the stored level.

## Broken locks

Bytes 12 to 15 of `XLOC` are a broken-lock counter. Every reference with `XLOC` starts locked
(flag 0x01), whatever the file says. Unlocking clears flag 0x01 and sets the counter to 0.

- The lock is broken when the counter is at least 1, or at least 2 when the player's perk entry
  point 16, "Ignore Broken Lock", gives more than 0.0001.
- A broken lock makes `GetLocked` return 2 and `GetIsLockBroken` return 1, and lockpicking it is
  refused with `sImpossibleLock`.
- No code was found that raises the counter, so in the vanilla game no lock breaks.

## The use-key gate

Every press of the use key goes through one gate before any listener hears it
([interaction](interaction.md)):

1. A Filter Activation perk of the player passes on the target: the press is refused
   ([perk entry points](perk-entry-points.md)).
2. No lock, or unlocked: the press goes on.
3. Locked, and the player carries the key: the lock opens, it stays open, and the press goes on.
4. Locked otherwise: the press is refused. Audio, scripts, and the inventory never hear it.

A refused pickable lock opens the lockpicking menu when the player has at least one lockpick
(the `LKPK` default object). When the lock opens, the original press runs again, so the door
opens or the container menu appears. Otherwise the HUD shows a notice: `sImpossibleLock` for a
lock that needs a key, `sNoLockPickIfCrimeAlert` while guards chase the player, and
`sOutOfLockpicks` without lockpicks. `sOutOfLockpicks` also shows
when the last pick breaks in the menu.

A carried key that opens a lock shows a notice too: `sOpenWithKey`, "Unlocked with %s.", with the
key's name for a door, and `sOpenedContainer` for a container. Which of the two the game shows for
which target is OpenSky's reading of their words.

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
| Sweet-spot widening | `fLockpickBrokenPicksMult` degrees for each pick this lock broke; 0 in the install | OpenSky's reading |
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
| Mod Lockpicking Crime Chance | 86 | `QuickHands` (0) | Scales the chance that a seen pick of an owned lock is reported. 0 means never |

A seen success, or a seen broken pick, on a lock the player may not open is a
[crime](crime.md). A reported broken pick closes the menu. A success counts "Locks Picked".

The perk runtime binds the lock as the locked reference, and the condition function
`GetLockLevel` (65) answers with its level. On any other reference, the function answers from
the reference's own lock: its stored level, 255 for a lock that needs a key, and 0 with no lock.
"Locksmith starts near the sweet spot" is OpenSky's reading of the entry point name.

## Skill use

An opened lock reports `fSkillUsageLockPick<band>` uses (2, 3, 5, 8, 13). A broken pick reports
`fSkillUsageLockPickBroken` (0.25). See [skill advancement](skill-advancement.md).

## The menu

The menu draws the install's 3D lock in the [menu scene](../rendering/menu-scene.md), over the
paused world:

| Mesh | Holds | Sequences |
| --- | --- | --- |
| `meshes\interface\lockpicking\lockpickshiv01.nif` | The lock, its cylinder `LockPickLockTumble`, and the shiv | `Intro`, `Rotate` |
| `meshes\interface\lockpicking\lockpick01.nif` | The pick, node `LockPick01` | `Intro`, `PickDamage`, `PickBreak` |

- Both `Intro` sequences play when the menu opens. The pick's `Intro` plays again for each
  fresh pick.
- The lock turn holds `Rotate` at a time: 0 at rest, and the time of the cylinder's largest
  turn when open. That time is found by sampling `Rotate`.
- The engine turns `LockPick01` by the pick angle, about the view axis through the node's
  own origin, which sits in the keyhole after `Intro`. `Rotate` turns the cylinder a quarter
  turn clockwise, and the pick turns with it, as it sits in the cylinder.
- `PickDamage` loops while the pick strains. `PickBreak` plays for 0.7 s after a pick
  breaks; that is where its flight ends.

The meshes do not hold the game's camera. The camera numbers are OpenSky's framing. The
lock is drawn unlit, with its diffuse texture, as every menu-scene mesh is. Below the lock,
the overlay keeps a turn bar, a pick health bar, the pick count, and the difficulty. When
the meshes fail to load, the overlay draws a 2D lock instead: the arc as dots, the pick, and
the keyhole turning with the lock.

| Input | Action |
| --- | --- |
| Mouse, A and D, left and right arrows | Move the pick |
| W or up arrow, held | Turn the lock |
| Escape | Leave |

These bindings are OpenSky's. The sounds are the install's `SNDR` records, found by editor ID:
`UILockpickingEnter`, `UILockpickingCylinderTurn`, `UILockpickingCylinderStop`,
`UILockpickingPickBreak`, and `UILockpickingUnlock`.

## Lockpicking menu

`Interface\lockpickingmenu.swf` draws the panel beside the lock: the skill meter, the lock
level, the picks left, and the button bar. The lock itself is the 3D lock above. The
engine calls `InitExtensions` and `SetPlatform(0, false)` once, then:

| Call | Arguments |
| --- | --- |
| `SetLockInfo` | skill level, next level, progress 0 to 100, level name, picks left |
| `UpdatePickAngle` | the pick angle in degrees |
| `UpdateLockAngle` | the lock turn times 90 |
| `UpdatePickHealth` | the pick health times 100 |

The level name is the `sLockLevelName<suffix>` text of the load order, such as "Adept".

## Saves

The `LOCK` chunk holds every changed lock ([save format](../formats/opensky-save.md)).
