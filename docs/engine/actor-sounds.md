---
type: Subsystem
title: Creature sounds
description: Where a creature's attack, breath, and machine sounds come from - its footstep
  set for the clip cues, and its NPC_ sound types for the loops.
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

[WARNING] The scrib (`DLC2AshHopperRace`) sends `NPCScribAttack1`. An `SNDR` of that name
exists, but no `FSTP` has the tag, and the scrib's set `NPCScribFootWalkFootstepSet` holds only
its steps. Its audio template has no attack sound type either. So no data route plays the
scrib's bite, and OpenSky plays none. Whether the game plays one is not observed yet, because
the reference bridge cannot name a playing sound.

## Loops come from the sound types

An `NPC_` record can carry sound types: a `CSDT` type, then each `CSDI` sound with its `CSDC`
chance (UESP, [NPC_](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_)). The types are
0 idle, 1 aware, 2 attack, 3 hit, 4 death, 5 weapon, 6 movement loop, and 7 conscious loop.

Most creatures take their sounds from an "audio template" actor through `CSCR` (Inherits
Sounds From). The Creation Kit locks the actor's own list while it inherits, so the template's
list replaces it ([Sounds Tab](https://ck.uesp.net/wiki/Sounds_Tab)). A template can name
another template.

In the install, 58 `NPC_` records carry sound types. All 58 have a conscious loop, 4 a
movement loop, and 1 an idle sound. For example, `AudioTemplateTroll` has
`NPCTrollBreatheLPSD`, and `AudioTemplateDwarvenSphere` has `NPCDwarvenSphereMovementLPMSD` and
`NPCDwarvenSphereConsciousLP`.

OpenSky plays:

- the conscious loop while the actor is alive and not unconscious;
- the movement loop on top while its mover moves it.

Each loop follows the actor and stops when the actor dies, moves away, or unloads. Only the
nearest `ActorLoopPlan.actorLimit` actors within `ActorLoopPlan.reach` units play their loops.
Both values are OpenSky's; the game's rule is not known.

`state actors` shows each actor's `soundLoops` by editor ID.

## Not handled yet

- The idle, aware, attack, hit, death, and weapon sound types. When the game plays them is not
  documented, and only one vanilla record (`AudioTemplateMudcrab`, idle) uses any of them.
