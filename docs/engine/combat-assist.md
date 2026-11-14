---
type: Subsystem
title: Combat assist
description: How the game helps an attack find its target - no melee magnetism for the player,
  NPC attack tracking, the soft auto-aim of the player's projectiles, and the flying-mount lock.
tags: [engine, combat, projectiles, ai, input]
---

# Combat assist

The game gives the player's aim a small push toward a target, but only for projectiles. Melee
swings get no help. NPCs keep facing their target while they attack.

OpenSky does not build any of this yet. A projectile flies exactly where the player aims
([spell delivery](/engine/spell-delivery.md)).

All values below are the ones that apply in play. Where `Skyrim.esm` overrides the program's
built-in default, the page gives the plugin value.

## Melee: no magnetism

The player's swings do not turn or slide the player toward a target. This holds for normal, power,
and sprint attacks, in first and third person. No such rule was found in the program.

## NPC attack tracking

When an NPC's combat logic starts a melee attack, the NPC keeps facing its target until the attack
ends.

- The track band runs from the attack's reach + 128 units to its reach + 512 units. A bash uses the
  bash reach, 141 units.
- The aim is refreshed every 0.25 seconds. It is refreshed every 0.1 seconds while the target is
  inside the band and is the high-priority target, which in practice is the player.
- The turn most likely uses the general actor turn speed of 2π radians a second.
- The NPC does not slide toward the target.

## Projectile auto-aim

Every projectile the player fires turns a little toward one chosen target. No check for a gamepad
was found, so this most likely applies to the mouse too.

### Picking the target

The game picks one target each frame. It needs the player to have 3D, a drawn weapon, and no state
that blocks it. A candidate is an actor in the high process level that:

- is not dead, has 3D, and is not the player's mount;
- is within 1800 units;
- has the centre and the top of its bounds both inside a screen window around the crosshair. The
  window's half-width is 6 × 0.005 of the screen;
- most likely is hostile, and is in combat.

From the candidates, the game takes the one closest to the crosshair, by the sum of its screen
offsets. A game option takes the nearest one instead, but it is off. Nothing keeps a target: it is
picked again every frame, so it drops as soon as it leaves the window, the range, or stops being
alive and hostile.

### Turning the projectile

When the projectile is launched, its direction turns toward the target by at most:

| Case | Largest turn |
| --- | --- |
| A spell, with the right hand empty or holding a melee weapon | 90° |
| Third-person camera | 2° |
| First-person camera | 1° |

Example: in first person, an arrow aimed 3° to the left of a deer in the window leaves 2° to the
left of it.

```mermaid
flowchart TD
    F[Player fires a projectile] --> T{Auto-aim target<br/>picked this frame?}
    T -- no --> S[Fly where aimed]
    T -- yes --> K{Spell, right hand<br/>empty or melee?}
    K -- yes --> A90[Turn toward the target, at most 90°]
    K -- no --> C{Third person?}
    C -- yes --> A2[At most 2°]
    C -- no --> A1[At most 1°]
```

## Flying-mount lock

While the player rides a mount whose race flies, as on a dragon, the Jump button locks a target.
By default each press flips the lock. With the toggle option off, the lock holds while the button
is held. Candidates are gathered within 7500 units on the ground plane.

While locked, each frame the game steers the mount:

- strafe term = the player's speed × the strafe input / 350;
- target term, only for a moving actor: the angle between the target's direction of travel and the
  player's heading, folded into −90° to 90°, × the target's speed / 350 × −2/π;
- f = 1 − distance / 750. While f is above 0, the heading changes by (target term − strafe term)
  × the strafe-heading factor × the frame time × f;
- the look input turns the heading and pitch, each scaled by its own factor.

| Target | Strafe-heading factor | Heading factor | Look factor |
| --- | --- | --- | --- |
| An actor | 0.5 | 1 | 10 |
| An object | 0 | 0.5 | 0.5 |

The steering stops while the target is gone or dead, all inputs are zero, the target is the
player's own mount, or the weapon is sheathed and the target is an actor.

## Source

Behaviour described from a clean-room read of `SkyrimSE.exe` 1.7.104.0. It is not yet confirmed
in the reference game.
