---
type: Subsystem
title: Bump reactions
description: What a calm NPC does when the player walks into it, and which game settings time it.
tags: [engine, ai, packages, dialogue]
---

# Bump reactions

When the player walks into a calm NPC, the NPC says a line, waits, steps aside, and then goes
back to its package. The settings come from the install. The CK wiki table
(<https://ck.uesp.net/wiki/Category:Settings>) names them without a use, so the order of the steps
is OpenSky's reading.

| Setting | Install | Use |
| --- | --- | --- |
| `fBumpReactionSmallDelayTime` | 1 s | The wait between the line and the step aside |
| `fBumpReactionIdealMoveDist` | 125 | How far the NPC steps, straight away from the player |
| `fBumpReactionMinMoveDist` | 75 | The step is never shorter than this |
| `fBumpReactionSmallWaitTimer` | 3 s | How long the NPC stays out of its package after the step. Also the wait before the same NPC says another bump line |

## What counts as a bump

The player touches an NPC when the two capsules overlap on the ground, with 4 units of room
(OpenSky's), and their feet are less than one player height apart. The NPC must be alive, not
fighting, not in a scene, and not the one the player talks to.

## The steps

1. The NPC leaves its package and says a line of the `DIAL` subtype `ACAC`, as its conditions
   allow, looking at the player.
2. After the delay, it walks to a point the step distance away from the player.
3. After the hold time, its package starts again.

An NPC that is already reacting does not start a second reaction. The timers run on the scene
clock: game seconds over the timescale. A reaction is not saved; a load drops it.

## Controls

World > AI & Navigation > Package shows how many NPCs react now, how many reactions ran since the
load, the step distance, the hold time, and the follower spacing.
