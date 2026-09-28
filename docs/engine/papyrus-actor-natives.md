---
type: Subsystem
title: Papyrus actor and faction natives
description: The Actor natives over actor values, death, combat, and draw state, the OnHit,
  OnDying, and OnDeath events, and the faction and relationship natives, with their citations,
  the signature check against the install, and the stated gaps.
tags: [engine, papyrus, actors, combat, factions]
---

# Papyrus actor and faction natives

These natives reach the world through [the world bridge](/engine/papyrus-activation.md#the-world-bridge).
Each goes through the subsystem that owns the state, so a script's change reaches the journal, the
dirty counts, and the save by the same path as any other change.

## Actor natives

| Native | What it does | Source |
| --- | --- | --- |
| `float GetActorValue(string)` | The current value | [GetActorValue - Actor](https://www.creationkit.com/index.php?title=GetActorValue_-_Actor) |
| `float GetBaseActorValue(string)` | The derived maximum | [GetBaseActorValue - Actor](https://www.creationkit.com/index.php?title=GetBaseActorValue_-_Actor) |
| `float GetActorValuePercentage(string)` | Current over maximum, 0 to 1 | [GetActorValuePercentage - Actor](https://www.creationkit.com/index.php?title=GetActorValuePercentage_-_Actor) |
| `DamageActorValue(string, float)` | Takes the magnitude off, down to 0 | [DamageActorValue - Actor](https://www.creationkit.com/index.php?title=DamageActorValue_-_Actor) |
| `RestoreActorValue(string, float)` | Adds the magnitude, up to the maximum | [RestoreActorValue - Actor](https://www.creationkit.com/index.php?title=RestoreActorValue_-_Actor) |
| `bool IsDead()` | The death latch, not health | [IsDead - Actor](https://www.creationkit.com/index.php?title=IsDead_-_Actor) |
| `bool IsInCombat()` | The combat behavior phase, searching included | [IsInCombat - Actor](https://www.creationkit.com/index.php?title=IsInCombat_-_Actor) |
| `StartCombat(Actor akTarget)` | Engages the actor against the player at once | [StartCombat - Actor](https://www.creationkit.com/index.php?title=StartCombat_-_Actor) |
| `StopCombat()` | Ends the fight and leaves hostility alone | [StopCombat - Actor](https://www.creationkit.com/index.php?title=StopCombat_-_Actor) |
| `bool IsWeaponDrawn()` | The melee draw state | [IsWeaponDrawn - Actor](https://www.creationkit.com/index.php?title=IsWeaponDrawn_-_Actor) |
| `Kill(Actor akKiller = None)` | Empties health, then kills | [Kill - Actor](https://www.creationkit.com/index.php?title=Kill_-_Actor) |

`SetActorValue`, `ModActorValue`, `ForceActorValue`, and `GetLevel` are registered too. Their rules
are on [actor values](/engine/actor-values.md) and [character leveling](/engine/character-leveling.md).

Both damage and restore use the magnitude of their argument. Both wiki pages say "Negative numbers
will be converted to positive so -100 and 100 will have the same effect".

`GetAV`, `GetBaseAV`, `GetAVPercentage`, `DamageAV`, and `RestoreAV` need no registration. The wiki
gives each as a Papyrus wrapper that calls the native, so compiled scripts reach the native
themselves.

Actor values are named by the vanilla table ([actor value names](/engine/actor-value-names.md)). A
name outside it is a tallied failure that names the value, never a zero.

## Stated gaps in the actor family

| Behavior | What OpenSky does | Why |
| --- | --- | --- |
| `Resurrect` | Not installed | Nothing clears the death latch. `RestoreActorValue` on a dead actor writes health and leaves it dead |
| `StartCombat` with a target other than the player | Tallied failure | OpenSky simulates no fight between two NPCs. Hostility has two cases and both are about the player |
| `Game.GetPlayer().IsInCombat()` | False during a fight | A combat behavior machine belongs to an NPC. Whether the player is in a fight is derived from every loaded actor, not stored on one |
| `IsWeaponDrawn()` on an NPC | Tallied failure | Only the player has a behavior graph that tracks drawing. "Sheathed" would be invented |

## OnHit

A hit queues `OnHit(akAggressor, akSource, akProjectile, abPowerAttack, abSneakAttack, abBashAttack,
abHitBlocked)` on every script on the target, in instance key order, at activation depth 0. A hit is
not an activation chain.

The player's melee swing, an arrow, and an NPC's blow report hits. Each reports after the damage is
applied, so a handler that reads the target's health sees the blow.

`akAggressor` is an ordinary handle. `akSource` and `akProjectile` name base records, not placed
references. Their handles name the record and resolve to no instance, so a handler can compare and
log them but cannot call a method on them. `abPowerAttack`, `abSneakAttack`, and `abBashAttack` are
always false, because those attacks do not exist yet.

## OnDying and OnDeath

A death queues both, in that order, on every script on the actor. The Creation Kit tells them apart
by time: "when the actor begins dying" and "when the actor finishes dying". OpenSky has one death
moment, the latch. Firing them some frames apart would invent a dying time the ragdoll hand-off does
not define.

The latch gives exactly once. It records a death only for an actor not already dead, and raises the
pair inside that check. So the per-frame zero-health check, a killing blow, a sidebar kill, and a
script's `Kill` together produce one of each. `Kill` empties health first and then takes the same
path, so `GetActorValue("Health")` and `IsDead()` never disagree. `akKiller` is `None` for a death
nothing caused, which is the wiki's default.

## Faction and relationship natives

These sit on the faction model behind [hostility](/engine/hostility.md).

| Native | What it does | Source |
| --- | --- | --- |
| `AddToFaction(Faction)` | Joins at rank 0. Nothing if already a member | [AddToFaction - Actor](https://ck.uesp.net/wiki/AddToFaction_-_Actor) |
| `RemoveFromFaction(Faction)` | Drops the membership | [RemoveFromFaction - Actor](https://ck.uesp.net/wiki/RemoveFromFaction_-_Actor) |
| `bool IsInFaction(Faction)` | Membership | [IsInFaction - Actor](https://ck.uesp.net/wiki/IsInFaction_-_Actor) |
| `int GetFactionRank(Faction)` | The rank. -2 for a non-member, -1 for a member ranked -1 | [GetFactionRank - Actor](https://ck.uesp.net/wiki/GetFactionRank_-_Actor) |
| `SetFactionRank(Faction, int)` | Sets the rank, joining if needed | [SetFactionRank - Actor](https://ck.uesp.net/wiki/SetFactionRank_-_Actor) |
| `int GetRelationshipRank(Actor)` | The signed rank, scripted over authored | [GetRelationshipRank - Actor](https://ck.uesp.net/wiki/GetRelationshipRank_-_Actor) |
| `SetRelationshipRank(Actor, int)` | Writes the rank to both actors | [SetRelationshipRank - Actor](https://ck.uesp.net/wiki/SetRelationshipRank_-_Actor) |
| `int GetFactionReaction(Actor)` | 0 Neutral, 1 Enemy, 2 Ally, 3 Friend | [GetFactionReaction - Actor](https://ck.uesp.net/wiki/GetFactionReaction_-_Actor) |
| `bool IsHostileToActor(Actor)` | The whole hostility order, for the pair | The install's own `Actor.pex`. No wiki page exists |
| `int Faction.GetReaction(Faction)` | The same numbers, between two factions | [Faction Script](https://ck.uesp.net/wiki/Faction_Script) |

Reading a membership first seeds the actor's authored `SNAM` list. A `Faction` script's `self` is a
form, not a placed reference, but factions are keyed by `ReferenceKey` too, so it resolves the same
way an `Actor` receiver does.

## Signatures checked against the install

A Papyrus signature is an interface that compiled mods already agree with: a wrong argument count
is a script that stops working. The wiki has been partly unreachable
([environment](/tools/environment.md)), and the shipped script cannot differ from the game. So a
real-data check loads the install's own `Actor.pex` and `Faction.pex` and compares, for each
registered function, the name, the `native` flag, and the parameter count. It also confirms the
functions left out on purpose are really absent, and prints their declared signatures.

The check changed two decisions the first time it ran:

- `Actor.IsHostileToActor` exists. No wiki page for it survives on any reachable mirror, and its
  condition function twin at xEdit index 719 has none either. The install declares
  `bool IsHostileToActor(Actor akActor) native`.
- `Actor.AddToFaction` is not native. Its whole body in the install is
  `if !IsInFaction(akFaction); SetFactionRank(akFaction, 0); endIf`. OpenSky's version follows that
  body, and registers it so it works even when the game's script is not loaded.

## Stated gaps in the social family

| Behavior | What OpenSky does | Why |
| --- | --- | --- |
| `Faction.SetReaction`, `Faction.ModReaction` | Not installed | Both write the `XNAM` table between factions, which is a read-only index here. A writer that did nothing would be worse than a counted gap |
| `Actor.ModFactionRank` | Not installed | No source says what the delta means for a non-member: join at the delta, or at zero. A guess would put a wrong rank in the save |
| A scripted relationship rank | Stored per reference pair, not per `NPC_` base | The player is one side in nearly every vanilla call and has no base record here. Vanilla scripts name unique actors, so nothing seen tests the difference |
| `RemoveFromFaction` on a crime faction | No effect | The crime faction comes from the place ([crime](/engine/crime.md)), so there is nothing to clear |
