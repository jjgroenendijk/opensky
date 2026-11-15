---
type: Subsystem
title: Creature sounds
description: Where a creature's attack, breath, and machine sounds come from - its footstep
  set for the clip cues, and its NPC_ sound types, which play on animation events.
tags: [engine, audio, creatures, footsteps]
---

# Creature sounds

A creature makes two kinds of sound besides its steps:

- a sound at one frame of a clip, such as a bite or a bark;
- a loop that plays while it lives, such as a troll's breath or a Dwemer sphere's gears.

## Clip cues come from the footstep set

A wolf's bite clip sends bare event names, such as `NPCWolfAttackA`. The canine bite clip
sends the cue of every canine at once: `NPCWolfAttackA`, `NPCDogAttack`, `NPCDogHuskyAttack`,
and `NPCDogDeathHoundAttackA` ([animation events](/engine/animation-events.md#events-the-game-ignores)).

These names are also `FSTP` tags. The install holds 191 `FSTP` records, and many carry a
creature cue as their tag. For example, `NPCWolfAttackAFootstep` (`Update.esm`) has the tag
`NPCWolfAttackA` and the impact data set `NPCWolfAttackAImpactSet`.

A creature's footstep set (`FSTS`) lists only its own cues:

| Footstep set | Plugin that adds the cues | Cues |
| --- | --- | --- |
| `NPCWolfFootWalkFootstepSet` | `Update.esm` | `NPCWolfAttackA`, `NPCWolfAttackB`, `NPCWolfAttackPower`, `NPCWolfBreathe`, `NPCWolfBark`, `NPCWolfHowl`, and more, in all five gait lists |
| `NPCDogFootWalkFootstepSet` | `Dawnguard.esm` | `NPCDogAttack`, `NPCDogAttackPower` |

So the event goes through the same route as a step: OpenSky looks the name up in the actor's
own set ([footstep sounds](/engine/footstep-sounds.md)). The wolf's set has no
`NPCDogAttack`, so a wolf plays one bite sound, not four.
`openskycli footstep --set NPCWolfFootWalkFootstepSet`
prints each cue with its sound file.

An event name that no `FSTP` record carries as a tag plays nothing, even when an `SNDR` has
that editor ID. Only an event of the form `SoundPlay.<editor ID>` names a sound directly
([animation events](/engine/animation-events.md#events)). For example, the scrib
(`DLC2AshHopperRace`) sends `NPCScribAttack1` when it bites. An `SNDR` of that name exists,
but no `FSTP` has the tag, and the scrib's set `NPCScribFootWalkFootstepSet` holds only its
steps. So the scrib's bite makes no sound, in the game and in OpenSky.

## Sound types

An `NPC_` record can carry sound types: a `CSDT` type, then each `CSDI` sound with its `CSDC`
chance (UESP, [NPC_](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_)). Each type
plays when the actor's graph sends the animation event of that type:

| Type | Name | Event |
| --- | --- | --- |
| 0 | Idle | `enum_idle` |
| 1 | Aware | `enum_aware` |
| 2 | Attack | `enum_attack` |
| 3 | Hit | `enum_hit` |
| 4 | Death | `enum_death` |
| 5 | Weapon | `enum_weapon` |
| 6 | Movement loop | `enum_movement` |
| 7 | Conscious loop | `enum_awake` |

No type plays on a timer, by distance, or by combat or movement state. The conscious loop also
starts when the actor's model is built, if the actor is not dead, and does not start a second
time while it plays. Every sound plays on the actor's model and follows it.

No vanilla behaviour or animation file sends an `enum_` event (a byte search of every archived
`.hkx` file, 2026-11-15). So in the vanilla game only the conscious loop plays, from the model
build. The other types play only for a mod whose clips send their events.

The sound list is the actor's own, or, when it has none, the list of the actor it names in
`CSCR` (Inherits Sounds From). The Creation Kit locks the actor's own list while it inherits,
so the template's list replaces it ([Sounds Tab](https://ck.uesp.net/wiki/Sounds_Tab)). Only
one step of inheritance counts: a template that inherits from another template gives no list.

When a type plays, its sounds are tried in order of chance, lowest first. Each try rolls a whole
number from 0 to 99, and the first sound whose roll is below its `CSDC` chance plays. When no
roll passes, nothing plays. So a chance of 100 always plays once it is reached, and a chance of
0 never plays. For example, a type with sounds A at chance 30 and B at chance 100 tries A
first: a roll of 12 plays A, and a roll of 64 moves on to B, which always plays.

### The mudcrab's idle sound

`AudioTemplateMudcrab` is the only vanilla record with an idle type, `NPCMudcrabIdle`. No
mudcrab clip sends `enum_idle`, so that type never plays. The mudcrab's look-left idle clip
(`meshes\actors\mudcrab\animations\idle_lookleft.hkx`) sends `SoundPlay.NPCMudcrabIdle`
instead, so the same sound plays each time that clip runs. In the reference game, a calm
mudcrab spawned in `QASmoke` made no sound at all for 95 seconds (2026-11-15, recorded with
`openskycli reference listen`).

## Loops

In the install, 58 `NPC_` records carry sound types. All 58 have a conscious loop, 4 a
movement loop, and 1 an idle sound. For example, `AudioTemplateTroll` has
`NPCTrollBreatheLPSD`, and `AudioTemplateDwarvenSphere` has `NPCDwarvenSphereMovementLPMSD` and
`NPCDwarvenSphereConsciousLP`.

OpenSky plays the conscious loop while the actor is alive and not unconscious, and the movement
loop only on its event. Each loop follows the actor and stops when the actor dies, moves away,
or unloads. Only the nearest `ActorLoopPlan.actorLimit` actors within `ActorLoopPlan.reach`
units play their loops. Both values are OpenSky's; the game's rule is not known.

`state actors` shows each actor's `soundLoops` by editor ID.
