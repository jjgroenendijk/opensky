---
type: Subsystem
title: Character shapes
description: The collision shape the game builds for a character from its skeleton's bound, and
  how OpenSky gives a long body, such as a horse, its front and back.
tags: [engine, physics, actors, collision]
---

# Character shapes

The game builds a character's collision shape from the `BBX` bound of its skeleton model, a
`BSBound` extra data block on the root ([NIF extra data](/formats/nif-extra-data.md)). The bound
is a centre and a half size on each axis, times the actor's scale. Source: a clean-room read of
`SkyrimSE.exe`, 2026-11-07. The bounds below were read from the install.

| Skeleton | Centre | Half size |
| --- | --- | --- |
| Human | (0, 0, 64) | (22, 14, 64) |
| Vampire lord | (0, 0, 72.5) | (22, 14, 72.5) |
| Horse | (0, 0, 84.52) | (31.82, 103.29, 84.52) |

Without a bound, the game uses a half size of 25 on every axis. A model flagged to use the
default gets (23, 17.5, 64).

## Upright bodies

When the height half size, hz, is at least both horizontal half sizes, the shape is an upright
capsule. Its radius is r = (hx + hy) / 2, and its segment runs ±(hz − r) about the centre. A
human gets r = 18 and a height of 128. The player uses the human skeleton, so the same capsule.
The game also builds an eight-sided prism with a pointed bottom of the same size, but it always
selects the capsule. Only a debug console command switches to the prism.

An NPC walks with this capsule once its skeleton's bound has loaded. Before that, and for the
player, OpenSky uses an upright capsule of radius 24 and height 128.

[WARNING] The player's capsule is not yet the game's radius 18.

## Long bodies

When a horizontal half size is larger than hz, the long axis is the larger of x and y. The radius
is r = min(other horizontal half size, hz). When r is less than 0.75 × max(other, hz), as for the
horse, the game builds three capsules:

- A body capsule along the long axis, of radius r, raised to z = (max − r) + max.
- Two short end capsules of radius max − r, about 8 units inside the ends of the body segment.
  They reach the ground.

A horse gets a body capsule of radius 31.8 at z of about 137, and end spheres of radius 52.7
centred 63.5 units in front of and behind its centre.

OpenSky keeps the upright capsule for the ground, the steps, and the slopes, and adds the two end
spheres. Each step, the ends slide with the planned move against the same collision the capsule
sees, and the larger push back changes the move. So an escort horse stops with its nose at the
prisoner cart instead of walking its head through it. The cart's bodies are on the props layer,
and the game's character layer collides with the props layer, so the cart blocks a horse that
does not tow it ([vehicles](/engine/vehicles.md)).

[WARNING] OpenSky lifts the end spheres by the walk step height, 32 units, so the ground under
them does not push the horse back on a slope. The game's ends reach the ground. The body capsule
is not built. The bound loads off the main actor; a mover that starts before it is ready walks
with the upright capsule alone until its next move.
