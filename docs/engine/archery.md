---
type: Subsystem
title: Archery
description: Drawing a bow and loosing an arrow on the behavior graph's events, the shot state
  machine, bow damage and the draw curve, stuck arrows, and input.
tags: [engine, combat, archery, behavior-graph, weapons]
---

# Archery

This page covers a bow shot, from the held mouse button to the arrow standing in a wall. It shares
the attack button, the graph event queue, and the impact chain with
[melee combat](/engine/melee-combat.md). The arrow's flight is on the
[projectiles](/engine/projectiles.md) page.

## The graph decides

The engine raises `bowDrawStart` when the attack button goes down and `attackRelease` when it comes
up. It does not decide that a draw began, how long it takes to reach full, or which frame the arrow
leaves the string. The graph decides all three and fires events back. This matters even more than
in melee: `arrowRelease` is the one frame an arrow comes into existence. A release from a clock
would create an arrow when the bow is not there.

One thing is timed: how long the button was held. UESP's draw damage curve depends on exactly that.
It measures the player's input, not the animation. The graph still decides when the arrow leaves.
The hold time only decides how hard.

## Graph names

Every name comes from the behavior census over the install. Each is declared by the third-person
`0_master.hkx` that OpenSky attaches, and also by `1hm_behavior.hkx`, `horsebehavior.hkx`, and the
`_1stperson` copies of both. Vanilla's capitalization is kept.

| Raised by the engine | Meaning |
| --- | --- |
| `bowDrawStart` | Start drawing. With a melee weapon, the same press raises `attackStart` |
| `attackRelease` | Loose. Shared with melee's held power attack: the same button coming up |
| `bowReset` | Give up the draw without loosing |

| Fired back by the graph | Meaning |
| --- | --- |
| `arrowAttach` | The nock: an arrow is now in the draw hand |
| `BowDraw` | The draw animation's own mark |
| `bowDrawn` | Full draw reached |
| `arrowRelease` | The spawn frame: the arrow leaves the string |
| `arrowDetach` | The arrow leaves the hand |
| `BowRelease` | The release animation's mark |
| `bowReset` | The draw collapsed on its own |

The only variable written is `bBowDrawn`. `iState_NPCBow`, `iState_NPCBowDrawn`, and
`iState_NPCBowDrawnQuickShot` are not written. The census gives their names and their `int32` type,
but nothing gives their encoding, and a guessed number would silently pick an animation set.
`bowZoom`, `bowZoomAmt`, and `bAimActive` are not written either: no graph on the install reads
them.

The crossbow release clips carry `bowZoomStop` right after `arrowRelease`. It ends the bow zoom
(below).

Archery is the third listener on the graph event queue, after footsteps and melee.

## The shot state machine

The state is a pure value over the fired names: no clock, no world, and no projectiles.

| Phase | Entered on | Meaning |
| --- | --- | --- |
| Idle | Start, `bowReset`, `BowRelease` | Nothing drawn |
| Nocked | `arrowAttach` | An arrow in the hand |
| Drawing | `BowDraw` | Pulling |
| Drawn | `bowDrawn` | Full draw. `bBowDrawn` is true here and only here |
| Loosed | `arrowRelease` | The spawn frame |

Loosed lasts exactly one frame, then returns to idle, like melee's contact frame. A graph that
fires `arrowRelease` and nothing else cannot stay in the spawn window. A release without a nock is
still a shot: the graph loosed an arrow, and refusing it would drop a real shot only to keep the
state machine tidy.

There is no draw and sheath machine here. Whether the bow is in hand is melee's draw state. This
machine only describes the shot on top of it.

## Damage

UESP "Skyrim:Archery", Detailed Bow Comparison, gives the combination:

```text
(bow damage + arrow damage) / time
```

So a shot's base damage is the `WEAP` damage plus the `AMMO` damage. The multipliers on top are
the normal weapon formula, from UESP "Skyrim:Weapons", Overview:
`(1 + skill/200) * (1 + perk effects) * (1 + item effects) * (1 + potion effect)`.

The Archery skill is fixed at 15, the value UESP gives for a starting skill without a race bonus.
The item and potion terms come from the Marksman Modifier and Marksman Power Modifier actor values,
which Fortify Archery enchantments and Fortify Marksman potions move. The perk term comes from
`Mod Attack Damage` ([perks](/engine/perks.md)). Smithing improvement is not applied. The shot
keeps the multiplier and the bow's enchantment from the moment it was loosed, so an arrow in the air
applies what the bow had then. An enchanted bow's arrow casts the enchantment on the actor it hits
and uses the bow's charge ([magic](/engine/magic.md)).

UESP "Skyrim:Archery", Draw Time and Damage Dealt, gives the draw curve, with `t` in frames of
1/60 s:

```text
35%   if t < 50 + 12 / (Speed * WeaponSpeedMult)
100%  if t > 50 + 52 / (Speed * WeaponSpeedMult)
(100/80) * (28 + Speed * WeaponSpeedMult * (t - 50))%   otherwise
```

UESP marks the middle branch as approximate: "the non-35%/100% formula's error is typically
between -0.1% and +0.2%. This may be due to floor functions or rounding errors". OpenSky does not
claim the middle branch matches the game exactly.

`Speed` is `WEAP` `DNAM` `speed`. `WeaponSpeedMult` is the graph variable melee writes from it.
With no extra multiplier they are the same number, so the draw fraction takes one speed value.

The draw fraction scales the launch speed as well as the damage. A quick shot is slower and drops
more, as well as hitting softer.

## Stuck arrows

An arrow that lands stays in what it hit. It uses the spawned object component that a dropped item
uses ([runtime state](/engine/runtime-state.md)). The base record is the `AMMO`, so a stuck arrow
uses the same ground model a spent arrow would be picked up as. The transform is the impact point,
turned along the flight direction. Roll is zero, because an arrow is round around its shaft.

The limit is UESP's: "Only 15 missed arrows or bolts can be present at once, once a 16th has been
fired the first one fired will despawn." It counts every stuck arrow, not only misses, because there
is no retrieval from a corpse and so no second kind to count.

- A cell that unloads takes its stuck arrows with it. Once per frame the loaded cells are compared,
  and arrows in cells that are gone are removed. An empty loaded set means nothing is streamed, and
  removes nothing.
- Arrows in flight are not saved. A teleport, a world state reload, or the despawn control removes
  them without resolving them.

Removal drops the arrow's whole world state entry, not a deletion mark. A spawned object exists only
because the world state says so. Dropping it leaves nothing behind in the next save.

A stuck arrow is placed in the world, not attached to the bone of the actor it hit. An actor that
walks away leaves the arrow where it landed.

## Input

The left mouse button reports both a press and a held state. Melee acts on the press, archery on
the hold. Capture loss clears the held state, so a button pressed inside the view and released
outside cannot leave a bow drawn forever.

Which one acts depends on what is equipped: a `WEAP` with `DNAM` animation type bow. The animation
type decides which attack set a weapon runs, so it is the right question. Crossbows are not done.

The arrow a shot uses is the equipped ammunition when it resolves to a flyable `PROJ`. With none
equipped, it is the first carried ammunition that does, in the inventory's fixed stack order. An
empty quiver stops the shot.

## Bow zoom

UESP says that with the Eagle Eye perk, "pressing Block while aiming will zoom in your view", that
the zoom drains stamina, and that it cannot start under the Slow Time shout
(<https://en.uesp.net/wiki/Skyrim:Archery>, <https://en.uesp.net/wiki/Skyrim:Eagle_Eye>). The perk
records give the numbers:

| Effect in the `PERK` | Entry point | Value | What OpenSky does |
| --- | --- | --- | --- |
| Eagle Eye | `Mod Bow Zoom` (20) | set 0.6 | The view's half-angle tangent is this share of normal |
| Eagle Eye | `Mod Power Attack Stamina` (27), bow only | set 10 | Stamina drained per second while zoomed |
| Steady Hand | `Bow Speed Bonus` actor value (78) | 0.75, 0.5 | The world and the player run at this speed while zoomed |

`Bow Speed Bonus` starts at `fDefaultBowSpeedBonus`, 1. The zoom starts when block is held, a
shot is nocked or drawn, `Mod Bow Zoom` gives less than 1, and the player has stamina. It ends
when one of these stops. It also ends on `bowZoomStop`, and then waits until block comes up.

`openskycli game state player` shows it under `bowZoom`: `zoomed`, `viewShare`, `timeScale`, and
`fovYDegrees`.

Where OpenSky differs:

- No source says what the `Mod Bow Zoom` number scales. OpenSky reads it as the share of the
  half-angle tangent, which is how a camera zoom scales the image.
- The drain is stamina damage, so regeneration pauses for `fDamagedStaminaRegenDelay` after the
  last drain. `fBowZoomStaminaRegenDelay` (3) is not used.

## Not done yet

Crossbows and bolts, explosive projectiles, AI archery, and picking up spent arrows.
