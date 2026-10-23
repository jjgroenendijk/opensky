---
type: Subsystem
title: Actor behaviour graphs
description: How each NPC and creature runs its race's Havok behaviour graph, how far from the
  camera a graph updates, and what its events and variables reach.
tags: [engine, animation, behavior, ai, app-ui]
---

# Actor behaviour graphs

Each loaded NPC and creature runs the Havok behaviour graph its race names, the same kind of
graph the player runs ([behaviour runtime](/engine/behavior-runtime.md)). The graph poses the
skeleton, fires animation events such as `FootLeft`, and holds the variables that conditions and
Papyrus read.

## Finding the graph

The race record names one behaviour graph per sex, a path under `Data\meshes`, for example
`Actors\Canine\WolfProject.hkx`. A female actor uses the female path when the race has one, else
the male path. OpenSky resolves the actor's race through its template chain
([actor records](/engine/actor-resolution.md)).

The path is a project file. It names a character file, and the character file names the behaviour
graph, the rig, and the clips. Some projects list few clips and let the behaviour find the rest
by folder, so OpenSky also offers every clip under the project's `animations` folder.

All actors of one race share one decoded project, one rig, and one clip cache. Only the graph
state is per actor. Decoding and clip loading run off the main actor; the frame drains them.

## Stepping

The graph steps in the world update, right after the idles, so an idle event raised this frame
reaches the graph in the same frame.

| Distance from the camera | Update |
| --- | --- |
| Up to the full-rate distance (default 2,048 units) | Every frame |
| Up to the graph distance (default 6,144 units) | 15 times a second |
| Further | Not at all; the actor keeps its last pose |

Both distances are settings, so a crowded scene can trade distance for frame time. The values
are OpenSky's; the game does not state its own.

Each step sets the locomotion variables from the actor's movement: `Speed`, `Direction`,
`TurnDelta`, `IsSprinting`, `IsSneaking`, `IsNPC`, and the player flags set to false. A change of
movement raises `moveStart`, `moveStop`, `SprintStart`, `SprintStop`, `SneakStart`, or
`SneakStop`.

## Pose

While a graph runs, it poses the actor. A combat or idle clip that overrides the pose still wins
while it plays. The mover still moves the actor: OpenSky ignores the graph's root motion, so the
path follower and the graph cannot disagree about where the actor stands.

A rider on a horse does not run a graph. It plays the rider clip of its mount's gait instead.

## Events and variables

Every event a graph fires goes where the player's events go: sounds and effects
([animation events](/engine/animation-events.md)), Papyrus `OnAnimationEvent`, and footsteps.
`FootLeft` and `FootRight` play a footstep at the actor's feet
(<https://ck.uesp.net/wiki/Animation_Events>). The footstep uses the default footstep set, because
OpenSky does not yet keep each NPC's boots after the cell is built.

A step farther from the listener than its sound's output model reaches is skipped before a voice
starts. Vanilla NPC steps use `SOMMono01800`, whose attenuation ends at 1,800 units, so the game
plays them silent there too. Starting a voice for every step in a full market halved the frame
rate in a Release benchmark.

`GetGraphVariableInt` and `GetGraphVariableFloat` read the actor's own graph
(<https://ck.uesp.net/wiki/GetGraphVariableInt>). Papyrus `PlayAnimation`,
`PlayAnimationAndWait`, `GetAnimationVariable*`, and `SetAnimationVariable*` reach the actor's
graph when the reference has no object graph.

An idle on a graph-driven actor is sent as its graph event, and the graph plays it. A held idle
ends with `IdleForceDefaultState`. No open spec names that event. The human graph of the install
declares it, next to `WeapEquip` (draw) and `Unequip` (sheathe).
