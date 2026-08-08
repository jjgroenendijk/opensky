---
type: Subsystem
title: Archery and projectiles
description: Drawing a bow, loosing an arrow, flying it on the fixed step, and what happens
  where it lands — including the measurement that settles what PROJ `gravity` means.
tags: [engine, combat, archery, projectiles, behavior-graph, proj, gmst]
timestamp: 2026-08-07T00:00:00Z
---

# Archery and projectiles

Roadmap item 15.5 (issue #196). A shot from the held mouse button to the arrow
standing in the wall. [Melee combat](/engine/melee-combat.md) is 15.4 and shares
this subsystem's button, its graph seam and its impact chain; death and ragdolls
are 15.6, the opponent that shoots back is 15.7, and perks, enchantments and
arrow retrieval from a corpse are M18.

Impl: `opensky/Engine/Combat/Archery*.swift` and `Projectile*.swift`, plus
`opensky/App/GameViewControllerArchery.swift` and its two satellites. The record:
[ESM records](/formats/records.md). The graph underneath:
[behavior graph runtime](/engine/behavior-runtime.md). The sweep it borrows:
[dynamic rigid bodies](/engine/dynamic-bodies.md). The health it takes off:
[actor values](/engine/actor-values.md). The spawn channel a stuck arrow rides:
[runtime state](/engine/runtime-state.md).

Out of scope for this item, deliberately: crossbows and bolts, enchanted and
explosive projectiles, AI archery, and picking a spent arrow back up.

## Contents

* [The rule, unchanged: the graph decides](#the-rule-unchanged-the-graph-decides)
* [Census-named events and variables](#census-named-events-and-variables)
* [The shot state machine](#the-shot-state-machine)
* [PROJ `gravity` is a multiplier, and that is a measurement](#proj-gravity-is-a-multiplier-and-that-is-a-measurement)
* [The flight model](#the-flight-model)
* [The archery GMSTs](#the-archery-gmsts)
* [Damage: the bow plus the arrow, times the draw](#damage-the-bow-plus-the-arrow-times-the-draw)
* [Impact: which query, and why](#impact-which-query-and-why)
* [Stuck arrows and the streaming lifecycle](#stuck-arrows-and-the-streaming-lifecycle)
* [Input bindings](#input-bindings)
* [What the vanilla graph actually does](#what-the-vanilla-graph-actually-does)
* [Verification surface](#verification-surface)

## The rule, unchanged: the graph decides

The engine raises `bowDrawStart` when the attack button goes down and
`attackRelease` when it comes up. It does not decide that a draw began, how long
it takes to reach full, or which frame the arrow leaves the string. The graph
decides all three and says so by firing events back, and `ArcheryState` reads
them.

That is [melee combat](/engine/melee-combat.md)'s rule applied to a shot, and it
matters more here rather than less: `arrowRelease` is the single frame a
projectile comes into existence, and a release invented from a clock spawns an
arrow at a moment the bow is not at.

One frame of archery, in order:

1. `ArcheryRuntime.acceptFrame(_:)` turns the held-button edges into raised
   events and advances the hold clock.
2. The fixed steps advance the graph, which is `LocomotionBridge`'s job.
3. `ArcheryRuntime.handleGraphEvents(_:)` advances `ArcheryState` on the drained
   names and, on `arrowRelease`, assembles the shot and hands it to
   `ProjectileRuntime`.
4. `ProjectileRuntime.advance(by:)` flies everything already in the air.

One thing *is* timed, and the distinction is worth stating because it looks like
an exception: how long the button was held. UESP's draw-damage curve is a
function of exactly that, and it measures the player's input rather than the
animation's phase. The graph still decides when the arrow leaves; the hold time
only decides how hard it leaves.

Step 4 runs outside the walk-mode gate the other three are behind. An arrow
already in the air has to finish its flight whether or not the player still has
control, or a shot freezes mid-air when the camera switches to fly mode. It
rides `Renderer.onWorldUpdate` rather than `onFrame`, chained onto the Papyrus
VM's and the actor-value tick's, so a menu-paused frame delivers zero and
nothing advances.

## Census-named events and variables

Every name comes from the M14 behavior census over the install
(`HKBBehaviorCensusRealDataTests`), never from memory, and every one is declared
by third-person `0_master.hkx` — the graph OpenSky attaches — as well as by
`1hm_behavior.hkx`, `horsebehavior.hkx` and the `_1stperson` copies of both.
Vanilla's capitalization is inconsistent and is reproduced rather than tidied.

Raised by the engine (`ArcheryGraphNames.raisedEvents`):

| Name | Means |
| --- | --- |
| `bowDrawStart` | begin drawing; the same press raises `attackStart` with a melee weapon |
| `attackRelease` | loose. Shared with melee's held power attack — the same button coming back up |
| `bowReset` | abandon the draw without loosing |

Observed coming back (`ArcheryGraphNames.observedEvents`):

| Name | Means |
| --- | --- |
| `arrowAttach` | the nock: an arrow is now in the draw hand |
| `BowDraw` | the draw animation's own annotation |
| `bowDrawn` | full draw reached |
| `arrowRelease` | **the spawn frame** — the arrow leaves the string |
| `arrowDetach` | the arrow leaves the hand |
| `BowRelease` | the release animation's annotation |
| `bowReset` | the draw collapsed on its own |

Variables written: `bBowDrawn` (bool) and nothing else.
`iState_NPCBow`, `iState_NPCBowDrawn` and `iState_NPCBowDrawnQuickShot` are
deliberately left unwritten for the reason `iRightHandType` is
([melee combat](/engine/melee-combat.md)): the census gives their names and
their `int32` type and nothing states the encoding, so a guessed integer would
select an animation set silently rather than visibly. `bowZoom`, `bowZoomAmt`
and `bAimActive` are absent because Eagle Eye zoom is a perk effect and perks
are M18's.

`ArcheryRuntime` registers the third cursor into `LocomotionGraphEventQueue`,
after footsteps and melee. Nothing about the queue changed to add it, which is
what item 15.4's promotion from drain-once bought.

## The shot state machine

`ArcheryState` is a pure value over the fired names: no clock, no world, no
projectiles, which is what makes its acceptance test a list of strings.

| Phase | Entered on | Means |
| --- | --- | --- |
| `idle` | start, `bowReset`, `BowRelease` | nothing drawn |
| `nocked` | `arrowAttach` | arrow in the hand |
| `drawing` | `BowDraw` | pulling |
| `drawn` | `bowDrawn` | at full draw; `bBowDrawn` is true here and only here |
| `loosed` | `arrowRelease` | the spawn frame |

`loosed` lasts exactly one batch: `endFrame()` returns it to `idle`, the same way
the melee contact frame closes, so a graph that fires `arrowRelease` and nothing
else cannot sit in the spawn window. A release with no preceding nock is still
accepted as a shot — the graph has loosed an arrow, and refusing it would drop a
real shot to protect a state machine's tidiness.

There is deliberately no draw-and-sheath machine here. Whether the bow is in
hand at all is already `MeleeCombatState.drawState`, and this machine describes
only the shot on top of it.

## PROJ `gravity` is a multiplier, and that is a measurement

Neither UESP nor xEdit states the unit of PROJ DATA's `gravity` member. UESP
"Skyrim:Archery" describes it only as "a gravity value, which determines how
quickly the projectile drops (higher is faster)", which is consistent with both
candidate readings and rules out neither.

The install settles it. Censusing the 134 PROJ records in `Skyrim.esm` by DATA
`type` (2026-08-07, `openskycli archery --census`, reproduced by
`ProjectileRealDataTests/censusesProjectileFlightFields()` into gitignored
`logs/projectile-census.log`):

| Type | n | `gravity` min/max/mean | `speed` min/max/mean |
| --- | --- | --- | --- |
| missile | 50 | 0.000 / 20000.000 / 400.293 | 32 / 99999 / 3910 |
| lobber | 6 | 0.000 / 0.000 / 0.000 | 1000 / 1000 / 1000 |
| beam | 12 | 0.000 / 0.000 / 0.000 | 1000 / 90000 / 29250 |
| flame | 17 | 0.000 / 0.000 / 0.000 | 0 / 20000 / 4294 |
| cone | 29 | 0.000 / 0.000 / 0.000 | 20 / 4000 / 1362 |
| **arrow** | **20** | **0.000 / 0.350 / 0.332** | **1000 / 15000 / 3960** |

Nineteen of the twenty arrow records carry a non-zero `gravity` and every one of
them is at most 1, while `speed` sits in the thousands. A member bounded by one
beside a member in the thousands is a dimensionless scale, not an acceleration
in units per second squared.

The arithmetic says the same thing outright. The vanilla iron arrow
(`IronArrow` -> `ArrowIronProjectile`, speed 3600, gravity 0.350) over 1,000
units of level flight:

* as a **multiplier** over the engine's world gravity: `a = 1400 * 0.35 = 490`,
  `t = 1000 / 3600 = 0.2778 s`, drop `= 0.5 * 490 * t² = 18.90` units.
* as an **acceleration** in units per second squared: drop
  `= 0.5 * 0.35 * t² = 0.0135` units.

The second is no drop at all. A shipped record does not carry a member that does
nothing on every projectile it has, so the multiplier reading is the one
`ProjectileFlight` implements.

Two things about the table are worth stating so nobody re-derives the wrong
conclusion from it. First, the *whole-set* figures do not show this: a handful of
`missile` records carry values into the thousands and drag the all-types mean to
149. The finding is about arrows. Second, the world gravity being multiplied is
this engine's single gravity constant, `WalkController.gravity` (1400 units/s²),
shared with the player capsule and every dynamic body — so an arrow and a
dropped crate fall at rates that stay in step if the constant ever changes.

## The flight model

There is no drag, so motion under a constant acceleration is exactly

```text
p(t) = p₀ + v₀t + ½at²        v(t) = v₀ + at
```

and `ProjectileFlight.step` is that closed form over one `dt` rather than an
approximation of it. Semi-implicit Euler — the integrator the
[dynamic-body solver](/engine/dynamic-bodies.md) uses — would accumulate a
`½a·dt²` error per step against the same curve, which is fine for a crate
settling on a floor and is not fine for a trajectory whose apex and impact point
the acceptance gate pins. Because it is exact, `apexHeight` and `drop(at:)` can
be checked in closed form rather than by re-running the loop.

`ProjectileRuntime` accumulates frame time and advances every projectile on
`WalkController.fixedTimeStep`, exactly as `DynamicBodyWorld` does and for
exactly the same reason: a shot fired from a given pose lands in the same place
on a 60 Hz display as on a 240 Hz one. Ordering is by projectile id, which is
allocation order, so two runs of the same session resolve impacts in the same
sequence.

The aim ray is the camera's forward direction rotated up about the horizontal
axis perpendicular to it, by the perspective's tilt GMST. Rotating the ray
rather than adding to its pitch means a shot aimed straight down is tilted by the
same angle as a level one instead of wrapping past vertical; a ray aimed exactly
along world up has no horizontal axis to pitch about and is left alone.

A shot is retired when it hits something, when its travel passes the shorter of
the PROJ's `range` and `fVisibleNavmeshMoveDist`, or when its PROJ `lifetime`
runs out. `travelled` is path length, not straight-line displacement: an arrow
lobbed in an arc has gone further than it has moved, and `range` bounds the
flight rather than the reach.

## The archery GMSTs

`ArcherySettings` resolves three, all from UESP "Skyrim:Archery", section "Range
and Trajectory":

| Setting | Documented default | Does |
| --- | --- | --- |
| `f1PArrowTiltUpAngle` | 2 | degrees the aim ray tilts up in first person |
| `f3PArrowTiltUpAngle` | 2.5 | the same in third person |
| `fVisibleNavmeshMoveDist` | 4096 | distance past which a shot can no longer hit anything |

**None of the three is a GMST record on this install.** Resolving them against
the active load order on 2026-08-07 (`openskycli gmst archery`) answers with the
documented fallback for all three, and neither `Skyrim_Default.ini` nor the four
quality presets beside it names any of them. UESP calls them "global game
settings" and they are engine defaults rather than data, so the source string
every one reports is "UESP-documented default" — the truth rather than a
degraded answer. The resolution is kept anyway: a mod that adds the GMST should
win, and the readout should say which plugin did it.

Two cross-checks fall out of the same page. UESP's parenthetical that "a weapon
with a reach of '1' has a reach of 141 distance units" is the same
`fCombatDistance` [melee combat](/engine/melee-combat.md) resolves to 141.000 on
this install, so the page and the install are talking about the same units. And
UESP notes that most projectiles have ranges "measured in the tens of
thousands", which the census confirms: every vanilla arrow carries `range`
60000, so `fVisibleNavmeshMoveDist` is what actually bounds a shot.

The two bolt settings (`f1PBoltTiltUpAngle`, `f3PBoltTiltUpAngle`) are not
resolved: crossbows are out of scope, and a setting nothing reads is a setting
that can go stale unnoticed.

## Damage: the bow plus the arrow, times the draw

Two documented pieces, both quoted rather than paraphrased.

UESP "Skyrim:Archery", Detailed Bow Comparison, gives the combination:

```text
(bow damage + arrow damage) / time
```

so a shot's base damage is the WEAP's plus the AMMO's. The multipliers on top of
it are the ordinary weapon-damage formula's — UESP "Skyrim:Weapons", Overview:
`(1 + skill/200) * (1 + perk effects) * (1 + item effects) * (1 + potion
effect)`.

Every one of those except the skill term is M18's — there is no Smithing
improvement, no perk tree and no enchantment in this engine to read them from —
so they enter as one `bonusMultiplier` defaulting to 1, which is what the formula
reduces to for a character with none. The Archery *skill* is in the same position
as melee's Block skill: `ActorValues` carries health, magicka and stamina only,
so `skill` is a parameter with a documented default of 15, the value UESP gives
for a starting skill with no racial bonus.

UESP "Skyrim:Archery", Draw Time and Damage Dealt, gives the draw curve, with
`t` in frames of 1/60 s:

```text
35%   if t < 50 + 12 / (Speed * WeaponSpeedMult)
100%  if t > 50 + 52 / (Speed * WeaponSpeedMult)
(100/80) * (28 + Speed * WeaponSpeedMult * (t - 50))%   otherwise
```

The page marks the middle branch approximate — "the non-35%/100% formula's error
is typically between -0.1% and +0.2%. This may be due to floor functions or
rounding errors" — and that caveat is carried rather than smoothed over. Nothing
in this engine claims the branch is the shipped one to the last decimal.

`Speed` there is WEAP DNAM `speed`, and `WeaponSpeedMult` is the graph variable
item 15.4 already writes from it; with no separate multiplier applied the two are
the same number, so `ArcheryDamage.drawFraction` takes one `speed` argument and
a caller with a real multiplier passes the product.

The draw fraction scales the launch *speed* as well as the damage, so a snap shot
is slower and drops further as well as hitting softer.

## Impact: which query, and why

The issue offered a choice — the 15.2 shape sweep, or a per-substep raycast
"where a ray is exact enough". It is split, because the two halves of the world
answer to different queries:

* **Static geometry: the 15.2 sweep.** A vanilla arrow flies at 3600 units/s, so
  a 1/120 s substep covers 30 units. A ray along that segment would be exact for
  an infinitely thin arrow, and an arrow is not thin: PROJ carries a
  `collisionRadius`, and honouring it is the difference between an arrow that
  clips a doorframe and one that slides past it. `ShapeSweeper.firstHit` sweeps a
  sphere of that radius along the segment and bisects the touch distance, and a
  zero radius degenerates to the ray without needing a second code path.
* **Actor capsules: the exact segment test.** `ShapeSweeper` answers against
  placed static shapes and knows nothing about actors, so the actor half reuses
  `MeleeHitDetector.closestApproach` — the same shortest-distance-between-two-
  segments narrowphase a swing uses. Against a capsule that is exact rather than
  conservative, and it costs one closed-form solve per actor per step. Each
  capsule is tested once against the whole step segment rather than at sampled
  points along it, so a thin actor cannot slip between two samples of a fast
  arrow, which at arrow speeds is not hypothetical.

Both halves run against the same travelled segment and the nearer touch wins, so
an arrow that passes an actor standing behind a wall hits the wall.

**One impact per projectile** is enforced by the projectile ceasing to exist, not
by an already-hit filter: there is no second step to filter. The shooter is
excluded by `ReferenceKey` rather than by distance, because the first step of a
shot starts inside the shooter's own capsule.

The impact sound walks the same IPCT chain a footstep and a melee hit do
([world sound](/engine/world-sfx.md)). An arrow has no INAM of its own — AMMO
carries no impact link — so the lookup runs with the unarmed profile's nil data
set and an arrow's impact is currently silent. The lookup is left in place so
that giving AMMO an impact link is a one-line change rather than a new chain.
The struck material is the ground material under the player, not the material of
the surface actually hit: nothing in this engine resolves a per-triangle material
at an arbitrary world point yet, the same limitation melee has.

## Stuck arrows and the streaming lifecycle

An arrow that lands is left standing in what it hit. The mechanism is
`ReferenceSpawnState`, the component a dropped item is drawn from
([runtime state](/engine/runtime-state.md)) — the one runtime-object channel this
engine has. The base record is the *AMMO*, so a stuck arrow is drawn from the
same ground model a spent arrow would be picked up as; the transform is the
impact point and a rotation derived from the flight direction, with roll left at
zero because an arrow is rotationally symmetric about its own shaft.

The cap is UESP's own: "Only 15 missed arrows or bolts can be present at once,
once a 16th has been fired the first one fired will despawn." It applies to every
stuck arrow rather than to missed ones alone, because this engine does not model
retrieval from a corpse and so has no second category to count.

Lifecycle, as item 15.5 specifies it:

* A cell that stops being resident takes its stuck arrows with it. The runtime
  reconciles against the streamer's resident set once per frame and removes the
  spawn for any arrow whose cell has gone — the same residency-reconciliation
  shape [dynamic bodies](/engine/dynamic-bodies.md) use. An empty resident set
  means "nothing is streamed" and evicts nothing.
* In-flight projectiles do not persist. A reset — a teleport, a world-state
  reload, the panel's despawn control — removes every one of them without
  resolving it, so nothing is written to a save and nothing lands in the cell the
  player just left.

Removal is `WorldStateStore.reset(key)` rather than a deletion component, because
a spawned object exists only because the store says so; dropping its whole delta
is what makes it gone and leaves nothing behind in the next save. That is exactly
what `WorldItemRuntime` does for a dropped item.

One honest limitation: the arrow is spawned at a world transform, not attached to
the *bone* of an actor it hit, so an actor that walks away leaves the arrow where
it landed. Attaching to a moving host is `RigidAttachment`'s job and needs an
actor-node transform channel the spawn path does not have.

## Input bindings

The left mouse button now reports both an edge and a level. Melee acts on the
press (`CameraInput.attack`) and archery on the hold
(`CameraInput.attackHeld`); the view sets both from one mouse-down and clears
only the level on the mouse-up. The level is also cleared on capture loss, so a
button that went down inside the view and came up outside it cannot leave a bow
drawn forever.

Which of the two acts is decided by what is equipped: `ArcheryIntent.hasBowEquipped`
is filled from WEAP DNAM `animationType == .bow`. The animation type is the field
that decides which attack set a weapon runs, so it is the right question to ask;
crossbows (`.crossbow`) are excluded because they are out of scope and the census
has not been read for whether their draw is data-identical.

The arrow a shot consumes is the first ammunition the player carries that
resolves to a flyable PROJ. "First carried" rather than "equipped", because
ammunition sits in its own EQUP slot that item 12.2 does not model, and the
inventory reports its stacks in a fixed order so the rule is predictable. An
empty quiver stops the shot: `consumeArrow` answers false and nothing goes in the
air.

## What the vanilla graph actually does

Probed on the local install 2026-08-07 by
`ProjectileRealDataTests/vanillaGraphAcceptsTheCensusNamedArcheryEvents()`: the
vanilla player graph declares a home for every one of the ten names above and for
`bBowDrawn`, with zero misses. Every constant in `ArcheryGraphNames` therefore
resolves against the shipping data — which is the claim no synthetic test can
make, and the one that fails loudly if a census reading was wrong.

What the graph does *with* a raised `bowDrawStart` is bounded by the same
unresolved encoding [melee combat](/engine/melee-combat.md) documents: the equip
sub-behavior branches on `iRightHandType`, which OpenSky leaves unwritten, so the
graph does not reach the states that would fire `arrowRelease` back. Until that
encoding is settled (issue #403), the graph-driven path raises correctly and
receives nothing, and the sidebar's Fire control is how an arrow gets in the air.
Both go through the same `ArcheryRuntime.loose`, so a shot taken from the sidebar
is indistinguishable downstream from one the graph released.

## Verification surface

`World > Combat & Physics > Archery` (`Destination-combatPhysics`,
`PanelSection-combatArchery`). The section shipped under
`World > Player & Locomotion` and moved with the M15 gate (issue #198).

| Control | Id | Does |
| --- | --- | --- |
| Fire one arrow | `ArcherySpawnControl` | fires one shot from the current aim, without spending an arrow |
| Despawn in flight | `ArcheryDespawnControl` | removes everything in the air, resolving nothing |
| Clear stuck arrows | `ArcheryClearStuckControl` | pulls every stuck arrow back out of the world |
| Clear shot trace | `ArcheryClearTraceControl` | empties the trace and the counts |
| Readout | `CombatArcheryStatsLabel` | shot state, bow and arrow, PROJ flight numbers, live count, last trajectory |

The readout's last line carries the three things the item asks for — spawn point,
impact point and flight time — plus the travelled distance and the drop.

All four controls are momentary, so all four are buttons: drawing is a held input
with no state a checkbox could set, which is the same three-way split
`LocomotionBindingsSection` makes for sneak, jump and run. The section is not
overridable, for melee's reason: an arrow in the air is world state, and a "Reset
all" that deleted it would undo something the user did on purpose.

CLI: `openskycli gmst archery` reports the three settings with their sources, and
`openskycli archery [--census] [--ammo <substring>]` walks the AMMO -> PROJ chain
and prints the census above.

Covering tests: `ProjectileRecordTests`, `ProjectileFlightTests`,
`ArcheryDamageTests`, `ArcheryStateTests`, `ProjectileRuntimeTests`,
`ArcheryRuntimeTests`, `PlayerLocomotionArcheryPanelTests`,
`LocomotionGraphEventFanOutTests`, and env-gated `ProjectileRealDataTests`.
