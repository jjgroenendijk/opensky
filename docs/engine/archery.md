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

The engine raises `bowAttackStart` when the attack button goes down and `attackRelease` when it
comes up. `1hm_behavior.hkx` leaves `Bow_Ready_State` for `Bow_AttackState` only on
`bowAttackStart`. `bowDrawStart` is an event the draw clip fires back; the Creation Kit list of
animation events shows it among the events of a shot (<https://ck.uesp.net/wiki/Animation_Events>).
`openskycli hkx meshes\actors\character\behaviors\0_master.hkx --set iRightHandType=7
--raise weapEquip --raise idle --raise bowAttackStart` shows the draw.

The engine does not decide that a draw began, how long it takes to reach full, or which frame the
arrow leaves the string. The graph decides all three and fires events back. This matters even more
than in melee: `arrowRelease` is the one frame an arrow comes into existence. A release from a clock
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
| `bowAttackStart` | Start drawing. With a melee weapon, the same press raises `attackStart` |
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
| `bowDrawStart` | The draw clip's own mark, fired back after `bowAttackStart` |

The only variable written is `bBowDrawn`. Archery writes no `iState_NPCBow*` value; the
[actor state graph](/engine/actor-state-graph.md) page says how `iState` reports a drawn bow.
`bowZoom`, `bowZoomAmt`, and `bAimActive` are not written either: no graph on the install reads
them.

The crossbow release clips carry `bowZoomStop` right after `arrowRelease`. It ends the bow zoom
(below).

## Crossbows

A crossbow is a `WEAP` with `DNAM` animation type crossbow. It raises `crossbowAttackStart`
instead of `bowAttackStart`; `1hm_behavior.hkx` enters `CrossBowDraw` on it. Stepping that graph
with `openskycli hkx` shows what happens next:

- `crossbowAttackStart` fires `BowDraw` and `bowDrawn` in the same step, so a crossbow has no draw
  time. A bolt always leaves at full draw: full damage and full launch speed.
- `attackRelease` fires `arrowRelease`, then the reload sounds. The graph enters
  `CrossBow_ReloadState` on `reloadStart` and leaves it on `reloadStop`. Both come from the clips,
  so the engine raises no reload event, and a press during the reload starts no new draw.

A crossbow fires only bolts, and a bow only arrows. A bolt is an `AMMO` without the Non-Bolt flag
(`DATA` flags bit `0x04`). The choice is otherwise the same as for arrows: the equipped one, else
the first carried one. An NPC with a crossbow picks bolts the same way. A bolt that hits counts
as a crossbow blow for the strike rules.

In the game a bolt tilts up 1 degree in first person and 2.5 degrees in third person, the same as
an arrow in third person. A sneak attack with a crossbow doubles the damage, as with a bow. The
Dawnguard perk `DLC1EnchancedCrossbowArmorPiercingPerk` halves the target's armour rating through
Mod Target Damage Resistance, when the crossbow has the keyword `DLC1CrossbowIsEnhanced`. No reload
time rule outside the behaviour graph was found.

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

The skill term is applied once, when the arrow hits, with the shooter's Archery at that moment.
The shot itself carries no skill term. The item and potion terms come from the Marksman Modifier
and Marksman Power Modifier actor values,
which Fortify Archery enchantments and Fortify Marksman potions move. The perk term comes from
`Mod Attack Damage` ([perks](/engine/perks.md)). Smithing improvement is in the bow damage: the
bow's profile carries the tempering bonus of the player's best copy, as a melee weapon does
([crafting](/engine/crafting.md#tempering)). The shot
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

The game program gives the same curve in seconds:

```text
elapsed  = draw time - 0.8
full     = (1.6667 - 0.8) / Speed
power    = 0.35                                 if elapsed <= 0
power    = min(1, 0.35 + 0.65 x elapsed / full)  otherwise
velocity = 0.2 + 0.8 x (power - 0.35) / 0.65
```

Example: Speed 1 and a draw of 1.3 s. `elapsed` is 0.5 and `full` is 0.8667, so the power is
`0.35 + 0.65 x 0.577 = 0.725`, and the launch speed is `0.2 + 0.8 x 0.577 = 0.66` of the `PROJ`
speed. A weak shot also falls faster. Its gravity is `fArrowWeakGravity` (1.75) less
(1.75 − the `PROJ` gravity) × the power. Example: a power of 0.35 with a `PROJ` gravity of 0.3 gives
1.75 − 1.45 × 0.35 = 1.2425. The result replaces the `PROJ` gravity. Only the player's bow shots
have a draw power; NPC shots and crossbows fly at power 1.

The draw fraction scales the launch speed as well as the damage. A quick shot is slower and drops
more, as well as hitting softer.

## Stuck arrows

An arrow that lands stays in what it hit. It uses the spawned object component that a dropped item
uses ([runtime state](/engine/runtime-state.md)). The base record is the `AMMO`, so a stuck arrow
uses the same ground model a spent arrow would be picked up as. The transform is the impact point,
turned along the flight direction. Roll is zero, because an arrow is round around its shaft.

The limit is UESP's: "Only 15 missed arrows or bolts can be present at once, once a 16th has been
fired the first one fired will despawn." It counts every stuck arrow, not only misses. An actor
shows at most 3, and a bolt sits 5 units deep instead of 20
([projectiles](/engine/projectiles.md#pick-up-bounce-and-stick-in-the-game)). A stuck arrow is a
placed `AMMO`, so the player takes it back with Take, or Steal where the item rules make it a theft.

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
type decides which attack set a weapon runs, so it is the right question. A crossbow acts the same
way (above).

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
| Eagle Eye | `Mod Power Attack Stamina` (27), bow only | set 10 | Stamina drained per second while zoomed. The entry point starts from `fBowZoomStaminaDrainMult`, 0 in the install |
| Steady Hand | `Bow Speed Bonus` actor value (78) | -0.5, then -0.25 more | The world and the player run at this speed while zoomed: 0.5 at rank 1, 0.25 at rank 2 |

`Bow Speed Bonus` starts at `fDefaultBowSpeedBonus`, 1. The perk text says time slows by 25% and
50%, but UESP notes that the real slowdown is 50% and 75%, which is what the records give
(<https://en.uesp.net/wiki/Skyrim:Archery>, Bugs). The zoom starts when block is held, a
shot is nocked or drawn, `Mod Bow Zoom` gives less than 1, and the player has stamina. It ends
when one of these stops. It also ends on `bowZoomStop`, and then waits until block comes up.

While zoomed, stamina regeneration stays paused, and the pause lasts `fBowZoomStaminaRegenDelay`
after the zoom ends. Skyrim.esm does not set this setting; the Creation Kit default is 3 seconds
(<https://ck.uesp.net/wiki/Category:Settings>). The drain itself is stamina damage, whose own pause
(`fDamagedStaminaRegenDelay`, 0.5 s) is shorter and so never decides.

`openskycli game state player` shows it under `bowZoom`: `zoomed`, `viewShare`, `timeScale`,
`fovYDegrees`, and `staminaPauseSeconds`.

Where OpenSky differs:

- No source says what the `Mod Bow Zoom` number scales. OpenSky reads it as the share of the
  half-angle tangent, which is how a camera zoom scales the image. A reference game capture of
  the same scene has not checked it yet.
- The pause after a zoom comes from the setting's name and its default, not from an observation.

## NPC archers

An NPC with a bow equipped stands off and shoots instead of closing to melee reach. It keeps the
combat loop's attack timing ([combat behaviour](/engine/combat-behavior.md)): the attack starts the
attack clip, and the contact step looses the arrow. It shoots from up to 2048 units, an OpenSky
value. The arrow is the first `AMMO` it has equipped or carries. A shot needs one, and does not use
it up.

The aim follows what was read from the game program:

1. **Lead.** The aim point is the middle of the target's capsule. Flight time is distance divided by
   the projectile speed, and the aim moves by the target's velocity times that time. This repeats up
   to 10 times and stops once the flight time changes by less than 0.05 s. There is no lead under 1
   unit or over 8192 units. The target's velocity is its movement over the last combat step.
2. **Noise.** Each axis of the aim point moves by a random amount up to ± variance × 16 units. The
   variance is 0.9. Both are program defaults with no record in the masters.
3. **Arc.** The launch solves the low ballistic arc for the projectile's speed and gravity, so no
   archery tilt-up is added. A point out of range is shot at 45 degrees.
4. **Spread.** The shot leaves the aim line by up to
   `fBowNPCSpreadAngle` × clamp((100 − Archery) / 100, 0, 1) degrees. The setting defaults to 5 in
   the program, and `Skyrim.esm` sets 4. The angle is uniform from 0 to that maximum, not uniform
   over the cone's area, so shots cluster near the centre. The direction around the line is uniform.
   The sine part goes to pitch and the cosine part to heading. Example: an NPC with Archery 40 shoots
   within 4 × 0.6 = 2.4 degrees of its aim. At Archery 100 there is no spread.

How an NPC archer picks its range and its shots, from the game program. Each value is a game
setting that the masters do not override.

- **Longest shot.** The ballistic range of the shot, speed² ÷ (gravity × world gravity), times
  `fCombatProjectileMaxRangeMult` (0.9), at most `fCombatMaximumProjectileRange` (4096).
- **Minimum range.** A longest shot past `fCombatRangedDistance` (1024) makes the weapon ranged.
  Its minimum range is then `fCombatRangedMinimumRange` (256), and at least the explosion radius.
  The minimum stays between 0 and the longest shot less 256. The 1024 is only this test; the archer
  does not try to stand there.
- **Preferred distance.** From the combat style: x is the defensive less the offensive multiplier.
  At x ≤ 0 the distance is Min + (Mid − Min) × (x + 1); above 0 it is Mid + (Max − Mid) × x. Min,
  Mid, and Max are `fCombatMaximumOptimalRangeMin`, `Mid`, and `Max` (1024, 1280, 1536).
- The archer's radius is added to the minimum and the preferred distance.
- **Where it stands.** It does not move while the target is between the minimum less
  `fCombatOptimalRangeMinBufferDistance` (256) and the preferred distance plus
  `fCombatOptimalRangeMaxBufferDistance` (512), at most the longest shot. Farther away, it walks
  to the preferred distance. Closer, it steps back to the minimum range. A target closer than
  `fCombatBackoffMinDistanceMult` (0.75) × the minimum range, inside a 60-degree view, makes it
  step back by the minimum less the distance. It keeps its path while the target's direction stays
  within `fCombatMaintainOptimalDistanceMaxAngle` (20 degrees).
- **Chance to shoot.** base = `fCombatRangedAttackChanceMin` (0.05) + (`Max` (1) − 0.05) ×
  the style's offensive multiplier. To that adds `fCombatRangedAttackChanceLastAttackBonus` (0.5) ×
  base × min(t ÷ `fCombatRangedAttackChanceLastAttackBonusTime` (10), 1), where t is the time since
  its last attack. Distance and line of sight play no part. Example: offense 0.5 gives a base of
  0.525, and 0.7875 once 10 seconds have passed.
- **Hold at full draw.** A random time from `fCombatRangedAttackHoldTimeAbsoluteMin` (0.1) up to
  1.5 + (0.25 − 1.5) × the offensive multiplier, from `fCombatRangedAttackHoldTimeMax` and `Min`.
  Within `fCombatRangedAttackHoldTimeMinDistance` (256) plus its radius, the offense counts as 1.
  Past `fCombatRangedAttackMaximumHoldTime` (10) the attack ends.
- The aim updates every `fCombatAimProjectileUpdateTime` (0.25 s).
- `fCombatProjectileMaxRangeOptimalMult` (0.85) and `fCombatRangedStandoffTimer` (6) exist as
  settings, but nothing reads them.

The lead and the noise above also hold for spells: a fire-and-forget spell has a variance of 0.5,
and a concentration spell 0.

The player's shots get no spread. The game also skips the spread under an "exact aim" flag of the AI;
what sets it was not found, so OpenSky never sets it.

## Not done yet

Explosive projectiles ([explosions](/engine/explosions.md)). NPC archers do not drive the bow graph
events above: they play the combat loop's attack clip. They shoot from up to 2048 units, not the
game's range rules above. A bolt tilts up 1 degree in third person, not 2.5.
