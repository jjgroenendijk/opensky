---
type: Subsystem
title: Projectiles
description: What PROJ gravity means and the census that settles it, the exact flight model,
  one shot model for arrows and spells, the range settings, and the impact query.
tags: [engine, combat, archery, projectiles, proj, gmst, magic]
---

# Projectiles

Arrows and spell projectiles fly through one pipeline. How a bow shot starts is on the
[archery](/engine/archery.md) page, and how a spell is cast on the [magic](/engine/magic.md) page.
The `PROJ` record is on the [item records](/formats/item-records.md) page.

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
[dynamic body](/engine/dynamic-bodies.md) solver uses, adds an error of `0.5 * a * dt^2` per step.
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
units", which is the same `fCombatDistance` the install gives ([melee combat](/engine/melee-combat.md)).
And UESP says most projectile ranges are "measured in the tens of thousands": every vanilla arrow
has `range` 60000, so `fVisibleNavmeshMoveDist` is what really limits a shot.

The two bolt settings are not read, because crossbows are not done.

## Impact

Static geometry and actors use different queries.

- Static geometry uses the shape sweep ([dynamic body contacts](/engine/dynamic-narrowphase.md)).
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
change. The material is the ground under the player, not the surface hit, as in melee.
