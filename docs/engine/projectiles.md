---
type: Subsystem
title: Projectiles
description: What PROJ gravity means and the census that settles it, the exact flight model,
  one shot model for arrows and spells, the range settings, and the impact query.
tags: [engine, combat, archery, projectiles, proj, gmst, magic]
---

# Projectiles

Arrows and spell projectiles fly through one pipeline. How a bow shot starts is on the
[archery](archery.md) page, and how a spell is cast on the [magic](magic.md) page.
The `PROJ` record is on the [item records](../formats/item-records.md) page.

## PROJ gravity is a multiplier

Neither UESP nor xEdit gives the unit of the `PROJ` `DATA` `gravity` field. UESP
"Skyrim:Archery" only says it is "a gravity value, which determines how quickly the projectile
drops (higher is faster)". Both possible readings fit that.

The install decides it. A census of the 134 `PROJ` records in `Skyrim.esm` by `DATA` type, from
`openskycli archery --census`:

| Type | Count | `gravity` min / max / mean | `speed` min / max / mean |
| --- | --- | --- | --- |
| missile | 50 | 0.000 / 20000.000 / 400.293 | 32 / 99999 / 3910 |
| lobber | 6 | 0.000 / 0.000 / 0.000 | 1000 / 1000 / 1000 |
| beam | 12 | 0.000 / 0.000 / 0.000 | 1000 / 90000 / 29250 |
| flame | 17 | 0.000 / 0.000 / 0.000 | 0 / 20000 / 4294 |
| cone | 29 | 0.000 / 0.000 / 0.000 | 20 / 4000 / 1362 |
| arrow | 20 | 0.000 / 0.350 / 0.332 | 1000 / 15000 / 3960 |

19 of the 20 arrows have a non-zero `gravity`, and every one is at most 1, while `speed` is in the
thousands. A field no bigger than 1 beside a field in the thousands is a scale factor, not an
acceleration in units per second squared.

The math agrees. The vanilla iron arrow (`IronArrow` to `ArrowIronProjectile`, speed 3600,
gravity 0.350) over 1,000 units of level flight:

- As a multiplier of world gravity: `a = 1400 * 0.35 = 490`, `t = 1000 / 3600 = 0.2778 s`, drop
  `= 0.5 * 490 * t^2 = 18.90` units.
- As an acceleration: drop `= 0.5 * 0.35 * t^2 = 0.0135` units.

The second is no drop at all. A shipped record does not carry a field that does nothing on every
projectile. So OpenSky reads it as a multiplier.

Two notes on the table. The figures over all types hide this: a few `missile` records have values
in the thousands, which pull the overall mean to 149. The finding is about arrows. And the world
gravity being multiplied is the engine's one gravity constant, 1400 units per second squared,
shared with the player capsule and dynamic bodies. So an arrow and a dropped crate stay in step if
it ever changes.

## The flight model

There is no drag, so motion under constant acceleration is exactly:

```text
p(t) = p0 + v0 * t + 0.5 * a * t^2        v(t) = v0 + a * t
```

Each step uses this closed form, not an approximation. Semi-implicit Euler, which the
[dynamic body](dynamic-bodies.md) solver uses, adds an error of `0.5 * a * dt^2` per step.
That is fine for a crate on a floor, but not for a path whose top and landing point are checked
exactly. With the closed form, apex height and drop can be checked directly.

Projectiles advance on the same fixed step as dynamic bodies. So a shot from one pose lands in the
same place at 60 Hz and at 240 Hz. They are ordered by projectile number, which is creation order,
so two runs resolve hits in the same order.

Flight runs outside the walk-mode gate. An arrow in the air must finish its flight even if the
player switches to fly mode. It runs on the world update, so a frame paused by a menu moves
nothing.

A shot ends when it hits something, when its path length passes the shorter of the `PROJ` `range`
and `fVisibleNavmeshMoveDist`, or when its `PROJ` `lifetime` runs out. Path length, not straight
distance, because an arrow in an arc has traveled further than it has moved.

## One shot model, two payloads

A spell projectile uses this same pipeline: the same integrator, fixed step, impact query, and
limits. Only what it carries and what it does on landing differ.

| | Arrow | Spell |
| --- | --- | --- |
| Costs | One `AMMO` from the quiver | Magicka, paid on release |
| Launch speed | `PROJ` speed x the draw fraction | `PROJ` speed |
| Aim ray | Camera forward, tilted up | Camera forward |
| On an actor | Health damage, and `OnHit` with the `WEAP` as `akSource` | The effect list, scaled by resistance |
| After impact | Sticks in the surface, at most 15 at once | Nothing stays |
| Provokes combat | Always | Only when the spell's effects are hostile |

The tilt lifts a bow shot above the crosshair to make up for arrow drop. A spell does not leave a
bow, so it flies straight down the aim ray. Healing a follower from range must not start a fight,
which is why provoking depends on the effects.

The aim ray is the camera's forward direction rotated up around the horizontal axis at right angles
to it. Rotating the ray, instead of adding to its pitch, means a shot aimed straight down tilts by
the same angle as a level one, instead of wrapping past vertical. A ray aimed exactly up has no
horizontal axis, and is left alone.

## Range settings

Three settings, from UESP "Skyrim:Archery", section "Range and Trajectory":

| Setting | Default | Meaning |
| --- | --- | --- |
| `f1PArrowTiltUpAngle` | 2 | Degrees the aim ray tilts up in first person |
| `f3PArrowTiltUpAngle` | 2.5 | The same in third person |
| `fVisibleNavmeshMoveDist` | 4096 | Distance past which a shot can no longer hit |

None of the three is a `GMST` record on the local install, and no default INI names them. UESP
calls them "global game settings". They are engine defaults, not data, so all three report the
source "UESP-documented default". They are still looked up, so a mod that adds one wins.

Two checks from the same page. UESP says "a weapon with a reach of '1' has a reach of 141 distance
units", which is the same `fCombatDistance` the install gives ([melee combat](melee-combat.md)).
And UESP says most projectile ranges are "measured in the tens of thousands": every vanilla arrow
has `range` 60000, so `fVisibleNavmeshMoveDist` is what really limits a shot.

A crossbow bolt tilts up by its own two settings instead. UESP gives `f1PBoltTiltUpAngle` a default
of 1 and names `f3PBoltTiltUpAngle` without one. Neither is a `GMST` on the local install, so both
fall back to 1 unless a mod adds one.

## Impact

Static geometry and actors use different queries.

- Static geometry uses the shape sweep ([dynamic body contacts](dynamic-narrowphase.md)).
  A vanilla arrow flies 3600 units a second, so one 1/120 s substep covers 30 units. A ray would be
  exact for an infinitely thin arrow. But `PROJ` has a `collisionRadius`, and honoring it is the
  difference between an arrow that clips a door frame and one that slides past. A sphere of that
  radius is swept along the step. A zero radius becomes a ray with no second code path.
- Actor capsules use the exact segment-to-segment test a melee swing uses. Each capsule is tested
  once against the whole step segment, not at sample points. So a thin actor cannot slip between
  two samples of a fast arrow.

Both run on the same segment and the nearer hit wins. An arrow passing an actor who stands behind a
wall hits the wall.

A projectile hits once, because it stops existing. The shooter is excluded by `ReferenceKey`, not
distance, because the first step starts inside the shooter's own capsule.

The impact sound uses the same `IPCT` chain as footsteps and melee. `AMMO` has no impact link, so
an arrow's impact is silent for now. The lookup stays, so giving `AMMO` an impact link is a small
change. The material is the one the sweep hit reports: the `MATT` type of the static shape struck.
An actor carries no material yet, so a hit on an actor uses the `IPDS` default entry.

## After the impact

These settings come from `Skyrim.esm`. Their names say what they do; no source gives a formula.

| Setting | Vanilla | What OpenSky does with it |
| --- | --- | --- |
| `fCombatMissileStickDepth` | 20 | A stuck arrow sits this far past the contact point, along its flight |
| `fAttachedArrowAgeMax` | 10 | An arrow stuck in an actor comes out after this many seconds |
| `iArrowInventoryChance` | 33 | Percent chance an arrow that hits an actor joins its inventory |
| `sNoArrows`, `sNoBolts` | text | The HUD notice for a press with no arrow; the bow does not draw |

UESP "Skyrim:Archery" confirms the 33% chance: "Arrows and bolts that hit an enemy have a 33% chance
of entering their inventory". The roll uses a seeded random source, so a test replays it. The
Hunter's Discipline perk doubles the chance through the `Mod Recover Arrow Chance` entry point
(21); the shooter's perks multiply the chance.

OpenSky reads the stick depth as how deep the shaft goes in. Where the `AMMO` model has its origin
is not confirmed, so the depth may need a sign or an offset once a capture shows the arrow.

An arrow stuck in an actor does not follow its bones, so it would float after the actor moves. The
age limit removes it after 10 seconds. A wall arrow has no age limit; only the cap of 15 removes it.

## Pick-up, bounce, and stick in the game

Each impact ends in one of four ways: the projectile vanishes, bounces, impales, or sticks.

- On a world surface, the material decides. A material that lets arrows stick holds the arrow.
  Any other material makes it bounce.
- A stuck arrow follows a moving physics body, or stays fixed on a static one.
- A bolt sticks 5 units deep, any other ammunition 20. An impaled arrow goes 12 units deep.
- A bounce turns the arrow into a free physics object. It leaves along its flight direction
  reflected about the surface normal, at a tenth of the `PROJ` speed. A bounced arrow does not
  stick. Example: an arrow with speed 5000 bounces off at 500 units a second.

At most 15 stuck projectiles stay in the world. A new one removes the oldest. An actor shows at most
3 arrows stuck in it, and a fourth replaces the oldest. Each one is removed after 10 seconds of
real time. These are only for show.

Activating a projectile in the world needs an actor as the activator:

- With the `PROJ` flag Can Be Disabled (`0x20`), and while the projectile is not disabled yet, it
  is disabled first. Its sound in flight stops, the `PROJ` disable sound plays where it is, and its
  explosion timer and proximity trigger stop, so it never goes off.
- With the `PROJ` flag Can Be Picked Up (`0x40`), the prompt is "Take", or "Steal" when it is
  owned, then the name, then "(count)" when the count is 2 or more. The `AMMO` is placed where the
  projectile is, with the same rotation, cell, and owner, and the activator activates it. The
  normal theft rules apply. There is no roll. Then the projectile is removed.
- Both steps can run on one activation. With neither flag, the activation does nothing.

An arrow that hits an actor joins its inventory on a roll of 0 to 99 below the chance. A
non-playable `AMMO` never joins.

### A deflected arrow

Only a hit on the shield's own collision body can deflect. The chance is the perk entry point Mod
Shield Deflect Arrow Chance, from 0, at most 100. A deflected arrow bounces, as on a material that
does not hold arrows. The weapon's enchantment and Apply Combat Hit Spell still run. Whether the
physical damage is cancelled was not found.

## Aim help in the game

The player's projectile turns a little toward a target near the crosshair.

- A target is an actor with full AI processing, alive, and within 1800 units. Its bounds on screen
  must be within 6 percent of the screen centre. The one nearest the crosshair wins.
- The shot turns toward it by at most 1 degree in first person, 2 degrees in third person, and 15
  degrees during a kill cam.
- The player's shot gets no lead for a moving target. During a kill cam it is aimed to make up for
  gravity.

Example: in first person a target sits 0.6 degrees off the crosshair. The shot turns the full
0.6 degrees. At 1.5 degrees off, it turns only 1 degree.

## Where OpenSky differs

- A bounce does not make a physics object. The arrow flies on as a projectile, with no more
  damage. Where it lands next, it lies at the contact point; one that falls on an actor is gone.
- A surface whose material OpenSky cannot name holds the arrow, and so does every surface when the
  load order has no material records.
- The `PROJ` flags Can Be Picked Up and Can Be Disabled are not read. A stuck arrow is a placed
  `AMMO`, so every one can be taken with the item rules. Every vanilla arrow sets Can Be Picked Up.
- An arrow sticks in an actor at the actor's position when it hit, not on a bone. No arrow
  impales.
- Any hit on an actor with a shield can be deflected, not only a hit on the shield's own body.
- The projectile kind (missile, arrow, beam, lobber) changes only the aim of a lobber.
