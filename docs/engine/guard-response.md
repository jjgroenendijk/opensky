---
type: Subsystem
title: Guards and arrest
description: Who is a guard, when guards confront or attack the player, paying and jail, and
  the crime condition functions and Papyrus natives.
tags: [engine, crime, factions, combat, papyrus]
---

# Guards and arrest

A bounty from [crime](/engine/crime.md) makes guards act. This page covers who is a guard, what
guards do, how an arrest ends, and the script surface.

## Who is a guard

An actor guards a crime faction when two things hold:

- it is a member of the faction named by the `GFAC` ("Guard Faction") default object;
- its `CRIF` names that crime faction.

Both were checked on the local install. `GFAC` names `IsGuardFaction`. Every one of the 463
`NPC_` records in it has a `CRIF` that it is also a member of. For example,
`GuardWhiterunImperialPatrolDay` reports to `CrimeFactionWhiterun`. `CRIF` is read through the
`useFactions` template flag, like `SNAM`. The Creation Kit: `Actor.GetCrimeFaction` "Obtains the
Faction this actor reports it's crimes to".

## Arrest or attack

The crime faction's `CRVA` has two flags. The Creation Kit's Faction page: "Attack on Sight: If
checked, guards will attack the player on sight if crime gold is high enough" and "Arrest: If
checked, guards will try to arrest the player".

The line is a pair of settings. The Creation Kit's Category:Settings page gives
`iAttackOnSightViolent` 2999 and `iAttackOnSightNonViolent` 0; the install sets neither, so the
wiki's values apply.

- Guards of an attack-on-sight faction fight once the violent half of the bounty is over 2999.
- The non-violent line is 0 in vanilla. OpenSky reads 0 as "no line": a theft bounty alone never
  makes guards fight. This is OpenSky's reading. Reading 0 as "any bounty" would make every guard
  fight over one stolen spoon, which the game does not do.
- Otherwise guards of an arresting faction confront the player.
- A faction without Arrest fights over any bounty. The Creation Kit tutorial "Creating a Custom
  Crime Faction": "If you don't check Arrest, guards will always try to kill the player on sight
  if there is a bounty".

## Hostility

Guard hostility is refreshed from the ledger every tick. A guard is hostile to the player when its
faction attacks on sight at the current bounty, or when the player resisted arrest by that
faction. Other actors get nothing from crime, and the record terms decide. Guard hostility ranks
above relationships and factions, so a guard who is the player's friend still arrests them
([combat](/engine/combat.md)).

## Confrontation

At most one guard confronts the player at a time: the nearest guard that perception has at
"detected", whose faction the player owes, and that would confront rather than fight.

- Farther than 192 units (the use-key reach), the guard's package is paused and it walks to the
  player. It finds a new path only after the player moves half that distance from where it was
  sent.
- Within reach, the session opens the load order's own guard dialogue. The dialogue's script
  fragments reach the ending through `PlayerPayCrimeGold` and `SendPlayerToJail`.

A conversation that closes with the bounty still owed is resisting arrest. UESP: "If you cancel
the dialogue when guards attempt to arrest you, they will attack you", and "Resisting arrest will
cause all guards in the area to attack you". So every guard of that faction turns hostile until
the bounty is gone. A conversation that could not open holds that guard back for one game hour.

A conversation that closes with the bounty cleared, but not through `PlayerPayCrimeGold` or
`SendPlayerToJail`, sent the guard away quietly: a bribe, a Thane's status, or the Thieves Guild.
It ends the [pickpocket](/engine/pickpocket.md) refusals charged to that faction.

This state lives in the session, not in a saved component, like the set of assaulted actors. A
loaded save starts every encounter again from the ledger.

## Paying and jail

| Ending | Effect |
| --- | --- |
| Pay (`PlayerPayCrimeGold`) | Refused unless the player's gold covers the bounty. Takes the gold and clears both halves of the bounty. The counts stay. By default it takes every stolen stack into the faction's `STOL` evidence chest, still stolen. `abGoToJail` moves the player to the `JAIL` marker |
| Jail (`SendPlayerToJail`) | Takes stolen goods, clears the bounty, and sends the player to the jail cell ([jail](/engine/jail.md)). A faction with no cell to enter passes the sentence at once and moves the player to the `JAIL` marker |

The Creation Kit describes the `JAIL` marker as "the spot where you'd be if you served time and
were released from jail".

The sentence is one day per `iCrimeDaysInPrisonMod` gold (100), at least one and at most
`iCrimeMaxNumberofDaysinJail` (7). This is OpenSky's reading of
UESP: "The maximum sentence is seven days ... You will serve the maximum sentence for any bounty
700 or higher". UESP is also the source for taking the goods: "If you choose to pay off your
bounty, all stolen items in your possession will be seized and put into the jail's evidence
chest".

The evidence chest is usually not loaded during an arrest. A loaded chest is written through its
placement. A chest that is not loaded is written under its reference key with no plugin starting
contents, so a chest first touched this way stops reading its `CNTO` list. On vanilla data this is
harmless: every `STOL` in `Skyrim.esm` places `EvidenceChestStolenGoods` or
`EvidenceChestPlayerInventory`, and neither has a `CNTO`. A faction with no `STOL` leaves the goods
with the player, because taking goods does not mean deleting them.

## Condition functions

From xEdit `Core/wbDefinitionsTES5.pas`:

```text
(Index: 459; Name: 'GetCrimeGold'; ParamType1: ptFactionNull)
(Index: 375; Name: 'GetCrimeGoldViolent'; ParamType1: ptFactionNull)
(Index: 376; Name: 'GetCrimeGoldNonviolent'; ParamType1: ptFactionNull)
```

The Creation Kit numbers are 4555, 4471, and 4472. The parameter may be null. A null parameter
asks about the hold the subject stands in, not about no faction. These cases report "unavailable"
instead of 0: no `FACT` data, a parameter naming a faction no plugin defines, and a null parameter
outside any hold ([condition evaluation](/engine/conditions.md)).

## Papyrus natives

Each signature is quoted from the Creation Kit wiki:

| Native | Signature |
| --- | --- |
| `Faction.GetCrimeGold` | `int Function GetCrimeGold() native` |
| `Faction.GetCrimeGoldViolent` | `int Function GetCrimeGoldViolent() native` |
| `Faction.GetCrimeGoldNonViolent` | `int Function GetCrimeGoldNonViolent() native` |
| `Faction.ModCrimeGold` | `Function ModCrimeGold(int aiAmount, bool abViolent = False) native` |
| `Faction.SetCrimeGold` | `Function SetCrimeGold(int aiGold) native`, the non-violent half |
| `Faction.SetCrimeGoldViolent` | `Function SetCrimeGoldViolent(int aiGold) native` |
| `Actor.SendAssaultAlarm` | `Function SendAssaultAlarm() native` |
| `Faction.SendAssaultAlarm` | `Function SendAssaultAlarm() native`. The wiki says it "finds a nearby member of this faction". OpenSky picks the resident member nearest the player, and charges the assault as `Actor.SendAssaultAlarm` does. With no resident member nothing happens |
| `Actor.SendTrespassAlarm` | `Function SendTrespassAlarm(Actor akCriminal) native` |
| `ObjectReference.SendStealAlarm` | `Function SendStealAlarm(Actor akThief)`. A theft of the object, charged only when it belongs to someone else |
| `Actor.GetCrimeFaction` | `Faction Function GetCrimeFaction() native`. `None` with no `CRIF` |
| `Actor.IsGuard` | `bool Function IsGuard() native` |
| `Faction.CanPayCrimeGold` | `bool Function CanPayCrimeGold() native` |
| `Faction.PlayerPayCrimeGold` | `Function PlayerPayCrimeGold(bool abRemoveStolenItems = True, bool abGoToJail = True) native` |
| `Faction.SendPlayerToJail` | `Function SendPlayerToJail(bool abRemoveInventory = True, bool abRealJail = True) native`. Both parameters are accepted and not read yet |
| `Game.ServeTime` | `Function ServeTime() native global`. Serves the sentence; fails when the player is not in jail |

A refused payment, or a sentence with no bounty, fails with a reason, so the script log says why
nothing happened.

The three alarms count as seen, without asking perception. The script says this actor caught the
criminal: "have this actor pretend he caught the specified criminal". Asking detection would let a
scripted alarm fail silently because the witness faced away. The wiki also notes the trespass alarm
"will not result in the 'time to go' dialogue that precedes the crime", so nothing warns first.

## Not done yet

- A faction with no cell to enter moves the player to the jail marker only when it is loaded.
- Guards do not arrest NPCs. A guard does not walk over to answer another actor's report. Only
  guards who see the player themselves act.
