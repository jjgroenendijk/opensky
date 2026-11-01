---
type: Subsystem
title: Follower commands
description: Follower command mode - how a follower in the favour state takes a target from the
  player, agrees or refuses, then walks there and uses it, and where OpenSky guesses.
tags: [engine, ai, followers, dialogue]
---

# Follower commands

A follower can be told to "do something". The player points at a target, and the follower
uses it: it opens a door, pulls a lever, sits down, picks up an item, loots a container, or
attacks an actor. Pointed at open ground, it walks there and waits. This mode is called
command mode.

Sources:

- The Creation Kit wiki "Favors Tab" page (<https://ck.uesp.net/wiki/Favors_Tab>) names the
  line for each step.
- The UESP "Skyrim:Followers" page, sections Commands and Morality, lists the orders and the
  crimes each morality level allows.
- `SetNoFavorAllowed` (<https://ck.uesp.net/wiki/SetNoFavorAllowed_-_ObjectReference>) marks an
  object a follower may not use.

## The lines

Each step plays a Favors tab topic of the follower's dialogue:

| Subtype | When |
| --- | --- |
| `SHOW` | Command mode starts. |
| `AGRE` | The follower accepts the target. |
| `REFU` | The follower cannot use the target. |
| `MREF` | The order is a crime that the follower's morality forbids. |
| `FEXT` | Command mode ends without an order. |

## Flow

1. The follower's "I need you to do something" topic runs a result script that calls
   `SetDoingFavor`. The favour flag turns on, the follower says `SHOW`, and command mode starts
   ([Dialogue](/engine/dialogue.md#favour-lines)). Holding the use key on the follower does the
   same, without the conversation ([Holding the use key](#holding-the-use-key)).
2. In command mode the use key does not activate the world. It gives the target under the
   crosshair to the follower instead. The crosshair reaches `fFavorRequestPickDistance` units.
   With nothing under the crosshair, the target is the first ground the view ray meets: static
   collision, or the terrain, tested every 32 units along the ray.
3. After a refusal, command mode stays open, so the player can pick another target.
4. After `AGRE`, command mode ends. The follower stops its packages, walks to the target, and
   acts. Then its packages run again and the favour flag turns off. No `FEXT` is said.
5. The pause key ends command mode with `FEXT`. In the game this is the Tab key; OpenSky has no
   Tab menu.

`IsDoingFavor` and `IsInFavorState` stay true while the follower walks to its target.

A follower's follow package comes from a quest alias. Alias packages run even while a
conversation holds the actor, so a command uses its own hold: no package of the follower runs
until the task ends.

## Holding the use key

UESP "Skyrim:Followers", section Commands: pointing at a follower and holding the use key
starts command mode. A press on a living player teammate waits:

- Released before 0.5 seconds, it is a tap. The follower is activated as by any press, so the
  conversation opens.
- Held for 0.5 seconds, command mode starts, as the topic starts it.

The page gives neither the time nor the distance. The 0.5 seconds are OpenSky's choice, and
the press reaches as far as any use-key press. A press on any other target acts at once.

## What the follower does

| Target | Action |
| --- | --- |
| Loose item | Picks it up into its inventory. |
| Container or dead body | Takes every item in it. |
| Door or activator | Activates it. |
| Furniture | Sits or lies down in its nearest free seat. |
| Living actor | Starts combat with it, from where it stands. |
| Ground | Walks to the spot and waits there, then follows again. |

A seated follower stays seated only while its own packages let it. Its follow package may get
it up again when the player walks away.

A locked door or container is unlocked first. The follower needs no lockpicks (UESP). A lock
that needs a key is refused with `REFU`.

The follower also refuses with `REFU` when the target is nothing, the follower itself, or an
object that a script marked with `SetNoFavorAllowed`.

## Morality

UESP gives the four morality levels:

| Morality | The follower commits |
| --- | --- |
| 0 | Any crime. |
| 1 | Violence against enemies, and property crimes. |
| 2 | Property crimes only. |
| 3 | No crime. |

OpenSky sorts each order into one crime kind:

- Property crime: taking an owned item, looting an owned container, or picking an owned lock.
- Violence: attacking an actor that is not already hostile to the player.

Violence needs morality 0, and a property crime needs morality 2 or lower. Attacking an enemy
is no crime. UESP says "you may be held responsible for the crime". OpenSky always reports the
crime against the player, run past the witnesses as the player's own crime is. Items taken by
theft arrive marked stolen.

## Settings

The Creation Kit wiki settings table lists three `fFavorRequest*` settings without a use. Each
use below is OpenSky's reading:

| Setting | Value | Use in OpenSky |
| --- | --- | --- |
| `fFavorRequestPickDistance` | 2100 | How far the crosshair reaches in command mode. |
| `fFavorRequestRadius` | 4000 | Command mode ends with `FEXT` when the follower is farther from the player. |
| `fFavorRequestWaitTimer` | 40 | Seconds the follower waits at a spot on the ground before it follows again. |

Command mode has no time limit in OpenSky. It ends with an order, the pause key, or distance.

The follower acts when it is 128 units from the target, which is OpenSky's choice.

## Checking it

`openskycli game debug favor <follower>` starts command mode as the topic does.
`openskycli game input hold activate --frames 40` on a follower starts it as a player
would; `input press activate` is a tap. `openskycli game debug teammate <ref>` makes any actor
a follower for this check.
`--target <ref>` then gives a target, or `--target x,y,z` a spot on the ground. `--exit` leaves
command mode. `openskycli game state
favor` shows the phase, the last decision, and how the last task ended.
