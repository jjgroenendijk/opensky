---
type: Subsystem
title: Combat loop
description: How a fight starts and ends - who is hostile, what makes an actor engage, derived
  combat state, how many fight at once, the script natives and events, transient caps, combat
  music, what a save keeps, the panel, and the known limits.
tags: [engine, combat, hostility, combat-ai, npc, music, persistence]
---

# Combat loop

The combat loop ties the pieces of a fight together: [melee combat](/engine/melee-combat.md),
[archery](/engine/archery.md), [death and ragdoll](/engine/ragdoll.md),
[actor values](/engine/actor-values.md), [detection](/engine/detection.md),
[navigation](/engine/navigation.md), [package schedules](/engine/package-schedules.md),
[dynamic bodies](/engine/dynamic-bodies.md), and [music](/engine/music.md).

Related pages:

- [Hostility](/engine/hostility.md): how records decide whether one actor attacks another.
- [Combat behavior](/engine/combat-behavior.md): the per-actor machine that approaches, attacks,
  blocks, flees, searches, and gives up, and the hit reactions.

## Hostility

Each actor has one hostility value: `neutral` (the start) or `hostile`, meaning it has a quarrel
with the player. It is stored as a world state component, so it is logged, counted, and saved like
every other write ([runtime state](/engine/runtime-state.md)). There is no `dead` value. Death is
its own component, and a second copy of the same fact would have to be kept in step.

The stored value is the session's explicit override: a record of something that already happened.
Three things write it:

1. The player hurt the actor. The melee hit and the projectile impact call the same function, so a
   swing and an arrow anger a target the same way. Calling it twice is safe.
2. The panel's hostility checkbox.
3. A script's `StartCombat`.

Everything else is derived from the records each time it is asked
([hostility](/engine/hostility.md)). With no game data loaded, there is nothing to derive from, and
the stored override alone answers.

## Entering a fight

Hostility is how an actor feels. Starting to fight is a separate step, with three causes:

| Cause | What happens |
| --- | --- |
| The player struck it | It is angered and staggered. It is in the fight for the step it takes to turn around |
| A script called `StartCombat` | It fights at once, without needing to perceive anything |
| It perceived the player | A hostile actor whose detection level reaches `detected` starts fighting, unhit |

So the panel's hostility checkbox does not start a fight by itself. An actor made hostile from the
sidebar stands there until it notices the player, like a bandit in a cave.

Being suspicious is not enough. A level between the two thresholds means something to investigate,
not a target.

## Combat state is derived

"Is the player in combat?" is not stored. It is derived every fixed step from the actors in loaded
cells: the player is in combat when some actor is engaged, meaning fighting the player or searching
for them.

This is not the same as "some actor is hostile". An actor that has not noticed the player, and one
that searched, gave up, and went back to work, are both hostile and both out of the fight. Deriving
from engagement is why the combat music stops when the fight ends, not when the actor is killed or
calmed.

The current target is the nearest hostile living actor, engaged or not, with ties going to the lower
`ReferenceKey`. From the player's side, "who am I fighting?" is answered by turning to face someone.
Nearest, not last hit, because a player who turned to a second attacker has answered by turning.

Deriving keeps it correct. A target that died, a cell that unloaded, and hostility cleared from the
panel all change the answer on the next step. A stored flag would need clearing in each place, and a
forgotten one would leave the player in combat with a corpse.

## How many fight at once

At most eight actors are engaged, the same as the most simultaneous movers. Every engaged actor asks
the mover for a path, so a ninth would be a fighter whose approach never starts. Past the limit the
nearest actors win, and the panel shows how many were crowded out. A silent cut would read as
"nobody else was fighting".

## Starting and stopping from a script

`StartCombat(Actor akTarget)` and `StopCombat()` are `Actor` natives
([Papyrus actor natives](/engine/papyrus-actor-natives.md)). Both go through the combat loop, not
straight to the component, so a script's fight enters by the same door as the player's.

- `StartCombat` engages the actor at once and records the target.
- Only the player is accepted as the target. Naming anyone else is a counted failure that says why.
- `StopCombat` ends the fight and leaves the stored hostility alone. The wiki's `StopCombat` stops
  the fighting. Changing how someone feels is a different function.

So an actor stopped mid-fight is still hostile and still in front of the player, and the next step
starts the fight again. A vanilla script that means it also calls `SetRelationshipRank`. The two are
separate calls.

## Script events

The melee, projectile, and combat loop paths all report hits the same way. A hit event carries
exactly the seven `OnHit` parameters the Creation Kit documents. Each path reports after the damage
is applied, so a handler that reads the target's health sees the blow. Three of the seven are always
false, because power attacks, sneak attacks, and bashing do not exist yet. The `akSource` and
`akProjectile` handles name base records with no script instance: a handler can compare and log
them, but cannot call a method on them.

Deaths come from the death latch in the ragdoll runtime. So `OnDying` and `OnDeath` fire exactly
once, whether a sword, an arrow, a sidebar control, or a script's `Kill` made the corpse. The death
panel counts these beside the graph-driven and fallback deaths, so "the scripts were told" and "the
graph drove it" are two numbers, not one guess.

The condition side reads the same state ([conditions](/formats/conditions.md)). `GetCombatState`
reads the behavior phase, not stored hostility: 0 for an actor that hates the player but has not
noticed them, 1 while fighting, and 2 while searching. Run-on type 3 (combat target) resolves as
above: the player fights the nearest hostile living actor, and every engaged living actor fights the
player.

## Transient caps

Four groups grow during a fight and none shrinks by itself. Without limits, a long session in one
room ends with a thousand of each.

| Group | Limit | Trim order | What a trim costs |
| --- | --- | --- | --- |
| Arrows in flight | 12 | Oldest first | Recorded as `.cancelled` in the trace |
| Arrows stuck in the world | 32 | Oldest first | Pulled back out |
| Corpses simulating | 8 | Oldest first | Stops stepping, keeps its resting pose |
| Dynamic bodies awake | 64 | Ascending `ReferenceKey` | Sleeps where it is |

The numbers are OpenSky's. Vanilla's caps are in its code, and no open source states them. Each was
picked from what the engine can carry at frame rate. Dynamic bodies are placed by the cell build and
have no spawn time, so they sleep in key order. Nothing is deleted from view: the cap costs motion,
not position.

## Combat music

Combat is a game system state, not a location. So entering combat selects a `MUSC` directly and
leaves the [music](/engine/music.md) precedence chain below it alone.

- Entering combat picks the first `MUSC` whose editor ID starts with `MUSCombat` (ignoring case),
  ordered by form ID so it is the same on every run. It remembers what it interrupted.
- Leaving combat restores exactly that, so a fight that started in a town ends in the town's
  playlist.
- Crossing a cell mid-fight updates what leaving will return to, and does not interrupt the fight
  music.
- A load order with no combat playlist leaves the music as it was and says why.

## What a save keeps

Hostility goes in `CBTS` and faction memberships in `FCTN` ([actor chunks](/formats/opensky-save-actor-chunks.md)).
`CBTS` holds only the explicit override, never the derived answer. Saving a derived answer would
freeze a decision the next load should make again: a plugin that changes a faction relation must
change who is angry. An unknown hostility byte loads as neutral.

Before a save, and after a load, the loop drops what a reload cannot rebuild: arrows in the air,
falling corpses, attack phases, and the damage flash. What stays is what a component holds:
hostility, actor values, and death. A fight saved mid-swing loads as a fight, without the swing.

## Controls

World > Combat & Physics > Combat Loop:

- Selected actor is hostile: reads the derived answer for the nearest actor, so a bandit shows
  hostile with nothing ticked, and a guard shows calm. Writing it sets the explicit override, which
  beats every record. Unticking a bandit keeps it calm. Clearing it also ends any fight and returns
  the actor to its package.
- AI casting: lets actors cast spells ([combat behavior](/engine/combat-behavior.md)).
- Clear hit trace.
- Readout: combat state and target, one line per fighting actor (phase, awareness, distance, health,
  and attack, contact, block, search, and cast counts, with how many spells it could cast from where
  it stands), the number crowded out, hits taken, the damage flash, and transients against their
  limits.

World > AI & Navigation > Combat Behavior has a second hostility checkbox for the actor selected
there. The first one follows the nearest actor, which is useless for following one guard through a
market. Both write the same component, so they never disagree.

A frozen physics simulation is the Combat & Physics destination's one change from default. A damaged
actor, an angry opponent, a corpse, and a shoved crate are world state, so they do not light the
sidebar dot and no reset undoes them.

## Limits

- No power attacks, bashing, or dodging.
- Actors cast only spells, and only the deliveries [magic](/engine/magic.md) carries out. Powers,
  lesser powers, and shouts are skipped. Summons and reanimation have nowhere to place a second
  actor.
- No group tactics or morale. Assistance is decoded and unread.
- Derived hostility is only asked about the player. The derivation takes any two actors, but
  engagement, perception, and the dialogue filter are all relative to the player.
- No ranged weapon AI. An actor closes to melee reach whatever it holds.
- Every actor swings unarmed. An NPC's equipment is resolved for drawing only, and turning a sword
  mesh into a damage number would be invented.
- An NPC's block is always `.weapon`, never `.shield`, for the same reason.
- NPCs have no behavior graph. A graph event raised on one returns false, and the trace says it did
  not play. Reactions are single clips ([actor animation](/engine/actor-animation.md)).
- Detection tracks observers against the player only, so an actor cannot lose a target that is not
  the player.
