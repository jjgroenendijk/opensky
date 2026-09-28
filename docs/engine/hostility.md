---
type: Subsystem
title: Hostility
description: How one actor's regard for another is derived from the session override, crime,
  relationships, and faction relations, how relationship ranks map to reactions, and how the AIDT
  Aggression value turns a reaction into a drawn weapon.
tags: [engine, combat, hostility, factions, relationships, npc]
---

# Hostility

The derivation answers what one actor makes of another. Two facts come out, and they are different:

- the reaction: what the records say about the pair;
- the hostility: whether that reaction, with this actor's own aggression, means a drawn weapon.

The [combat loop](/engine/combat.md) asks it about the player. The records are on the
[factions](/formats/factions.md) and [relationships](/formats/relationships.md) pages.

## Order of the terms

Asked what `observer` makes of `target`, the derivation takes the first term that answers:

| Order | Term | Source of the answer |
| --- | --- | --- |
| 1 | Session override | The stored hostility: the panel, `StartCombat`, or the player's blow |
| 2 | Crime | Guards and a bounty ([guard response](/engine/guard-response.md)) |
| 3 | Relationship | A rank a script set, else the `RELA` rank between the two `NPC_` bases |
| 4 | Faction | The `FACT` relations between the two actors' memberships |
| 5 | Default | Neutral |

Only row 3's place comes from a source. The Creation Kit wiki says "relationships override factions"
(<https://ck.uesp.net/wiki/Relationship>). The rest of the order is OpenSky's:

- The override is first because it records something that happened this session. An actor the
  player stabbed does not calm down because the records say they are friends.
- Crime is next, because a bounty is also something the player did.
- Faction comes before the default.

Each answer carries the term that produced it, so a panel or a test can say why an actor is angry.

## The four reactions

The Creation Kit uses four reactions, from friendliest to most hostile: `ally`, `friend`,
`neutral`, and `enemy`. A `FACT` `XNAM` holds one directly. A `RELA` rank maps onto them in the
groups the wiki gives:

| Reaction | Relationship ranks |
| --- | --- |
| `ally` | Lover, Ally |
| `friend` | Confidant, Friend |
| `neutral` | Acquaintance, Rival, Foe |
| `enemy` | Enemy, Archnemesis |

Rival and Foe are Neutral, not Enemy. Two actors who dislike each other do not attack on sight
unless one of them is Very Aggressive, which is how strangers are treated too.

A raw value outside either named range gives no reaction, not a guessed one, and the relation index
counts the `XNAM` entries it dropped. The vanilla install has none.

When an actor's memberships disagree about the same target, the most hostile one wins. That is
OpenSky's rule: no source says what an actor in both an allied and an enemy faction thinks. Leaning
to the enemy reading keeps a quest faction that marks someone an enemy from being cancelled by an
unrelated friendly membership, which would be invisible in play. Both directions of a pair are read,
because vanilla does not always write the mirror `XNAM`, and a relation that names the pair at all
is an opinion about it.

A script-set rank wins over the written one inside row 3. That is what `Actor.SetRelationshipRank`
means, and it is the only way a relationship with the player can count: the player has no `NPC_`
base for a `RELA` record to name.

## Aggression draws the weapon

The reaction alone decides nothing. The Creation Kit puts that on the actor, in the `AIDT`
Aggression value, "in conjunction with Faction Relationships"
(<https://ck.uesp.net/wiki/AI_Data_Tab>):

| Aggression | Attacks on sight |
| --- | --- |
| Unaggressive | Nobody |
| Aggressive | Enemies |
| Very Aggressive | Enemies and neutrals |
| Frenzied | Everybody |

An aggression value the spec does not name attacks nobody. An actor with no readable `AIDT` is
unaggressive. Guessing upward, into a drawn weapon, is the harmful direction.

This table is why a vanilla bandit is hostile to the player with nobody touching the panel. No
`FACT` relation and no `RELA` record names the pair, so the reaction is the default, Neutral. The
bandit is Very Aggressive, and Very Aggressive attacks neutrals. A Whiterun guard next to it gets the
same Neutral reaction and stays calm, because a guard is only Aggressive.

Confidence is decoded but not used here. "Cowardly actors NEVER engage in combat" is about engaging,
and hostility records regard.

## Memberships at runtime

The derivation reads the runtime faction membership component
([factions](/formats/factions.md#membership-at-runtime)), not the `NPC_` record. So an actor a quest
added to the Companions stays in after a reload, and an actor the player was never near costs
nothing until something asks.

Seeding walks the actor's template chain once per actor per session. The derivation itself is not
cached. It is two component reads, a pair lookup, and a walk of two short lists. A cache would have
to be cleared on every world state write, and actor values are written sixty times a second.
