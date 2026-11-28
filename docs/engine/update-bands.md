---
type: Engine
title: Update bands
description: How far from the camera per-object work runs every frame or less often, which systems
  use the bands, and how a skipped frame's time is kept.
tags: [engine, performance, actors, rendering]
---

# Update bands

Work for an object far from the camera runs less often than work for a near one. The game
also updates far actors less often. One rule, the update bands, sets how often for every
system that uses it, so a far actor moves, looks, and smokes at the same reduced rate.

The bands and their rates are OpenSky's choice. The game does not use distance bands for this: it
switches each actor's package procedures between a full and a cheap version by its
[process level](ai-process-levels.md#procedures-by-level).

## The bands

| Band | Distance from the viewer | The work runs |
| --- | --- | --- |
| `full` | up to 1,024 units | every frame |
| `near` | up to 2,048 units | 30 times a second |
| `reduced` | up to 6,144 units | 15 times a second |
| `distant` | further | 5 times a second |

The distances are those of the [actor graphs](actor-graphs.md#stepping). A graph
stops past 6,144 units, where other work keeps the `distant` band.

## Keeping the time

Each object has its own clock. A frame that skips the work adds its time to the clock, and
the next run steps by all the time waited. So a far mover covers the same ground as a near
one, in fewer and longer steps. Example: in the `reduced` band at 60 frames a second, a mover
steps every fourth frame, by 4/60 s each time.

A new clock waits a share of its first interval less, taken from the object's FormID or
placed position. So objects that start together run their work in different frames, and no
single frame pays for all of them. The share is the same on every run.

When an object comes near, its next frame runs the work at once, with the time it waited.

## Systems that use the bands

| System | Viewer | What a skipped frame skips | Longest wait |
| --- | --- | --- | --- |
| NPC movement | the camera | the mover's path step and its walk | 1/15 s |
| Perception | the nearest target, the player | building the observer again | 1/5 s |
| Particle systems | the camera | the particle simulation | 1/15 s |

- **NPC movement.** The walk also takes longer fixed steps when far: 1/120 s in the `full`
  band, 1/60 s in `near`, and 1/30 s further out. Without this, a walk that steps less often
  would still run as many fixed steps. A step stays under the walk's frame cap of 0.1 s, so no
  time is lost. Turning on the spot and push slides still run every frame.
- **Perception.** The roster keeps each far observer's last position and facts between its
  refreshes. The detection checks themselves already run a few pairs per step
  ([detection](detection.md)).
- **Particles.** A system that follows the camera, such as rain, is always near, so it runs
  every frame.

## Grass

Grass groups hold every instance of one model across the loaded cells, so a group has no
single distance. Instead, each group keeps a list of its instances near the camera: those
that pass the density test and lie within the draw distance plus 1,024 units. The per-frame
distance, view, and budget tests then walk this list only. The list is built again once the
camera moves from where it was built. Each group allows a different distance, from 512 to
1,024 units, so the rebuilds of different groups fall in different frames. While the camera
stays within 1,024 units, every instance inside the draw distance is on the list, so no grass
appears late.

## Reading the bands

`openskycli game state actors` shows `bands` for each actor: the band at its camera
distance, and the band its movement and perception use. `state frame` shows `updateBands`:
how many particle systems stepped in each band, and how many grass lists were built in the
last frame ([game commands](../tools/game-commands.md)).
