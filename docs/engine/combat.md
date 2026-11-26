---
type: Subsystem
title: Combat loop
description: How a fight starts and ends - who is hostile, what makes an actor engage, derived
  combat state, how many fight at once, the script natives and events, transient caps, combat
  music, what a save keeps, and the known limits.
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
Two things write it:

1. The player hurt the actor. The melee hit and the projectile impact call the same function, so a
   swing and an arrow anger a target the same way. Calling it twice is safe.
2. A script's `StartCombat`.

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

Being suspicious is not enough. A level between the two thresholds means something to investigate,
not a target.

## Combat state is derived

"Is the player in combat?" is not stored. It is derived every fixed step from the actors in loaded
cells: the player is in combat when some actor is engaged against the player or the player's allies,
meaning fighting them or searching for them.

This is not the same as "some actor is hostile". An actor that has not noticed the player, and one
that searched, gave up, and went back to work, are both hostile and both out of the fight. Deriving
from engagement is why the combat music stops when the fight ends, not when the actor is killed or
calmed.

An actor whose current AI package has the Ignore Combat flag is never engaged, and leaves a fight it
was in. The Creation Kit wiki says such an actor does not fight or flee, but still counts as in
combat for condition functions (<https://ck.uesp.net/wiki/Package_Flags>). OpenSky does not count
it: it stays out of the fight in every way.

The current target is the nearest hostile living actor, engaged or not, with ties going to the lower
`ReferenceKey`. From the player's side, "who am I fighting?" is answered by turning to face someone.
Nearest, not last hit, because a player who turned to a second attacker has answered by turning.

Deriving keeps it correct. A stored flag would need clearing in each place, and a forgotten one
would leave the player in combat with a corpse.

## How many fight at once

At most eight actors are engaged, the same as the most simultaneous movers. Every engaged actor asks
the mover for a path, so a ninth would be a fighter whose approach never starts. A silent cut would
read as "nobody else was fighting".

## Allies

A summoned or reanimated actor serves its caster ([magic archetypes](/engine/magic-archetypes.md)).
The CK wiki puts it "under the caster's control". The loop calls such an actor an ally.

- The player's ally is calm toward the player, and the player's blows do not turn it.
- It fights the foe nearest to it among the actors that fight the player within 2048 units of the
  player. It engages without having to see the foe.
- With no foe, it walks back when it is more than 300 units from the player, and stops 150 units
  away. These three distances are OpenSky values; no record names them.
- A foe fights the nearest of the player and the player's allies that it has detected. A foe that a
  script sent at the player with `StartCombat` keeps the player.
- A blow on an ally uses the same damage formula as a blow on the player. The player's hit reaction,
  the hit trace, and the Block skill use stay with blows on the player.
- An NPC's ally shares its caster's regard for the player, so it fights the player as its caster
  does, and walks after its caster between fights.
- An NPC that casts at an ally or a foe aims at that actor, not at the player.
- Allies take what is left of the engagement cap after the foes.

## NPC foes

An NPC fights another NPC as well as the player. The rule is the game's
[hostility test](/engine/hostility.md#aggression-draws-the-weapon): an actor attacks on sight the
actors its aggression and reaction make it hostile to, and it is hostile to a target that fights it,
unless it counts that target an Ally or a Friend.

- Each living NPC finds the NPCs within 4096 units that it is hostile to on its own detection
  pass, as each High-level actor does in the game. After each pass the next comes a random 1 to 2
  seconds later. The game waits 2.5 to 5 seconds when the scene counts as complex; OpenSky has no
  such test. A combat target is picked again at once when it is no longer valid, else 1 second
  after the last pick, or 3 seconds after a pick that changed it. The player's allies are left
  out; they keep the rules above.
- Perception tracks each such pair. When the observer detects its foe, it fights it.
- An actor that an NPC fights, fights back. It engages without having to see the attacker.
- A calm actor that helps an ally fighting an NPC fights that NPC too, through Assistance
  ([Confidence and Assistance](/engine/combat-behavior.md#confidence-and-assistance)).
- An actor that fights the player picks the nearest of the player, the player's allies it has seen,
  and its NPC foe. While it has a foe, a player it has not detected does not pull it away.
- The player is in combat only while an actor fights the player or the player's allies. A fight
  between two NPCs plays no combat music.
- `openskycli game state actors` shows each actor's combat `target`.

The range is an OpenSky value. The game checks detection every 1 to 2 seconds per
actor ([detection](/engine/detection-schedule.md#who-runs-detection-in-the-game)).

## Who an assisting actor fights

Each actor asks one question of each other actor near the player: would it help that actor? The
`GetShouldHelp` condition function asks the same question
(<https://ck.uesp.net/wiki/GetShouldHelp>). With A as the helper and B as the actor it helps, the
checks run in this order. Some of them ask the question again with another actor in A's or B's
place, and every check runs again for the new pair.

1. A always helps itself.
2. A commanded actor, such as a summon, is judged through its owner. When B has an owner, the
   answer is whether A helps that owner. Then, when A has an owner, the answer is whether that
   owner helps B.
3. The Morality filter, for a helper whose Morality is not "any crime". All three other values
   act the same. It stops A from helping a B that started its fight or committed a crime. When it
   stops A, a follower B is judged as the player instead; any other B gets no help.
4. A follower A helps the player, unless A would attack the player on sight for crimes. A
   follower A never helps a B in a fight against the player or against A. Otherwise it helps B
   when the player would help B, judged with the player's own Assistance and Morality.
5. A follower B counts as the player: A helps B when it would help the player.
6. A never helps a frenzied B, an actor whose Aggression is 3.
7. A helps B when its Assistance is "helps allies" and its reaction to B is ally, or when its
   Assistance is "helps friends and allies" and the reaction is ally or friend.

A follower is an actor in the player-teammate state. The check itself has no chance, no timer, no
detection, and no distance.

### Started the fight

An actor gets the mark of having started a fight when it starts fighting while it fights nobody:

- It attacks an actor that is not hostile to it and carries no mark itself. So a victim that
  fights back gets no mark, and two enemies that meet get none.
- It attacks the player while hostile to the player by its own Aggression and reaction. Fighting
  the player for the player's crimes gives no mark.
- It joins a fight on a side whose first fighter has the mark: it takes that fighter's mark.
- A script starts its fight, and it is not a guard.

The mark goes when that actor's fight ends. A helper still helps a marked B when the helper
already fights, or is hostile to, one of B's opponents.

### Committed a crime

B has committed a crime for the filter in two cases, and the hostility exception above does not
apply to them:

- B is the player, and the player resists arrest by the helper's crime faction. While that faction
  counts the player as an enemy, this holds for 300 seconds after the player resisted. Otherwise
  it holds while a guard fights the player.
- At least one guard responds to B's crime. At most 4 guards respond to one actor's crime. The
  count goes back to 0 when the crime alarm on B ends, such as at an arrest or a paid fine.

A would attack the player on sight for crimes when:

- A is a guard and the player's violent bounty with A's crime faction is above 2,999 gold, or the
  non-violent bounty is above its own line, which is off in the vanilla game.
- A is not a guard, and A's crime faction counts the player as an enemy, for 24 game hours after
  it began, or the crimes A knows the player committed are worth 100 gold or more.

A asks only while B is alive and in a fight, while both are loaded near the player, and while A
detects B. No distance is checked. A joins the fight on B's side and takes no target from B. It
then picks its own target from everyone B's side fights. So it turns against the player only when
the player is one of B's opponents, and only for that fight; no faction or relationship changes.

A does not join when it would also help one of B's opponents, or when it is hostile to anyone on
B's side.

A witness to an assault or a murder can help the victim against the attacker. That needs the
witness to help the victim and not help the attacker. When the attacker is the player, the
witness also stays angry with the player after the fight.

In OpenSky, the checks above run in this order for each calm actor within 2,048 units of an ally
in a fight. Perception tracks each such pair, so the helper asks only once it detects the ally.
The follower is the actor a script made the player's teammate, and the owner is the actor that
commands a summon. The 300 seconds of resisting arrest are counted in game seconds. Every target
counts as having AI. A helper of an ally fighting an NPC takes that NPC as its foe, unless it
would help that NPC too.

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
is applied, so a handler that reads the target's health sees the blow. The player's swing sets
`abPowerAttack`, `abSneakAttack`, and `abBashAttack` for a power attack, a sneak attack, and a bash,
and an arrow sets `abSneakAttack`. An NPC's blow is a plain swing, so it sets none. The `akSource` and
`akProjectile` handles name base records with no script instance: a handler can compare and log
them, but cannot call a method on them.

Deaths come from the death latch in the ragdoll runtime.

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
| Arrows stuck in the world | 15 | Oldest first | Pulled back out |
| Corpses simulating | 8 | Oldest first | Stops stepping, keeps its resting pose |
| Dynamic bodies awake | 64 | Ascending `ReferenceKey` | Sleeps where it is |

The stuck-arrow limit is UESP's: "Only 15 missed arrows or bolts can be present at once"
([Archery](https://en.uesp.net/wiki/Skyrim:Archery)). The other numbers are OpenSky's. Vanilla's
caps are in its code, and no open source states them. Each was
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

## Fall damage

The walk controller keeps the highest point of a fall and reports the drop when the actor lands.
A drop above `fJumpFallHeightMin` hurts: damage is
`(height - fJumpFallHeightMin) * fJumpFallHeightMult` raised to `fJumpFallHeightExponent`. The
player and NPCs use separate settings (`fJumpFallHeight*` and `fJumpFallHeight*NPC`). A landing
slower than `fJumpFallVelocityMin` does no damage. The perk entry point `Mod Falling Damage`
scales it, and for the player the difficulty's damage-to-player multiplier does too, at most 1.
The formula follows the setting names; no open source gives it. `openskycli game state player`
shows the last fall under `lastFall`.

## Limits

- NPCs do not power attack, bash, or dodge. The player power attacks, sneak attacks, and bashes.
- Actors cast only spells, and only the deliveries [magic](/engine/magic.md) carries out. Powers,
  lesser powers, and shouts are skipped.
- No group tactics or morale.
- The dialogue filter and the stored hostility override are relative to the player only.
- An NPC swings the first weapon it has equipped, with its `WEAP` damage and reach and its
  tempering, as the player's weapon is read. With none it swings unarmed. An NPC with a bow shoots
  ([archery](/engine/archery.md#npc-archers)).
- A combat event aimed at an NPC, such as a stagger from the player's swing, goes to that NPC's
  behaviour graph ([actor graphs](/engine/actor-graphs.md)). An NPC that runs no graph, or whose
  graph lacks the event, answers false, and the trace says it did not play. The combat loop's own
  reactions are single clips ([actor animation](/engine/actor-animation.md)).
