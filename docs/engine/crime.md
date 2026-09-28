---
type: Subsystem
title: Crime and bounty
description: Ownership and who may use a thing, which crime faction answers for a place, the
  four crimes and their prices, witnesses, the bounty ledger, and stolen goods.
tags: [engine, crime, factions, inventory, runtime-state]
---

# Crime and bounty

A take that reaches someone else's property is theft. Theft that someone sees costs gold. The
goods stay marked as stolen whether anyone saw or not. What guards then do is on the
[guards and arrest](/engine/guard-response.md) page.

## Ownership

Ownership answers one question: does this actor own, or may it freely use, that reference?

The first match wins:

1. The reference's own `XOWN`.
2. The `XOWN` of the cell it stands in.
3. No owner.

The rules do not merge. A chest in an owned shop that names its own owner belongs to that owner
only.

The data needs the cell step. UESP: "an item's name that appears in red text means that the item
is owned and picking it up is stealing" ([Skyrim:Crime](https://en.uesp.net/wiki/Skyrim:Crime)).
Every crate in Belethor's shop reads as owned, but has no `XOWN` of its own. On the local install
the cell `WhiterunBelethorsGeneralGoods` has one `XOWN`, and Breezehome, the house the player
buys, has none.

`XOWN` names either an `NPC_` or a `FACT`, and nothing in the field says which. So it is found by
lookup: a link the load order has a `FACT` for is a faction owner, and anything else is an actor
owner. A link that resolves to nothing is still an actor owner, not "no owner". Reading a broken
owner as free would make a shop lootable the moment a plugin went missing.

Who may use it:

- An actor owner matches on the `NPC_` base, because that is what `XOWN` names. Every `ACHR` from
  that base is the owner. The player has no base record here and matches none.
- A faction owner matches a member at or above the rank in `XRNK`. With no `XRNK`, the rank is 0,
  the lowest rank vanilla uses, so any member may use it. A negative rank, which vanilla writes for
  "a member the rank titles do not name", does not meet a rank 0 requirement.

The answer is one of: no owner, permitted, forbidden. Only forbidden is theft.

## Which crime faction answers for a place

A cell names its location with `XLCN`. A location names its crime faction with `FNAM`. Almost no
location has one: it is set at the hold, and places inside inherit it by following `PNAM`
upward. On the local install:

```text
WhiterunBelethorsGeneralGoodsLocation  PNAM -> WhiterunLocation      (no FNAM)
WhiterunLocation                       PNAM -> WhiterunHoldLocation  (no FNAM)
WhiterunHoldLocation                   FNAM -> CrimeFactionWhiterun
```

The first `FNAM` found on the way up wins. A `PNAM` loop stops at a location already visited
([locations](/formats/locations.md)). UESP: "Bounties are tracked separately for each of Skyrim's
nine holds and you will only incur a bounty in the hold in which you commit a crime."

A chain with no `FNAM` has no crime faction. That is a real answer: a dungeon or a road belongs
to no one, which is why killing a bandit on the road costs nothing. No default is used. A broken
`FNAM` link also stops the walk. Skipping past it would charge the wrong hold.

## The four crimes

The crimes are theft, assault, murder, and trespass. They are the four that the `FACT` `CRVA`
field prices and that this engine can observe.

The prices come from the record, not from game settings. `openskycli gmst list --prefix iCrime`
on the local install shows two settings, `iCrimeGoldStealHorse` (100) and `iCrimeGoldWerewolf`
(1000), and neither prices these four. `CrimeFactionWhiterun`'s `CRVA` reads "murder 1000,
assault 40, trespass 5, pickpocket 25, steal multiplier 0.5000, escape 100, werewolf 1000".
UESP's bounty table gives the same numbers.

| Crime | Bounty | Source |
| --- | --- | --- |
| Theft | Item value x steal multiplier, rounded down | `CRVA`, and UESP "Half of the stolen item's value, rounded down" |
| Assault | `CRVA` assault (40 in Whiterun) | `CRVA`, and UESP "Assault ... 40" |
| Murder | `CRVA` murder (1000) | `CRVA`, and UESP "Murder ... 1000" |
| Trespass | `CRVA` trespass (5) | `CRVA`, and UESP "Trespassing ... 5" |

Rounding down makes a one-gold item free. Nothing adds a minimum. A `CRVA` too short to hold a
steal multiplier (the field came in a later record version) uses a multiplier of 1, so the full
value is charged. Zero would make every theft from that faction free, which is the worse error.
A faction with no `CRVA` charges nothing, but the crime is still counted.

Faction flags control the charge. `trackCrime` must be set. The ignore bit for the crime
(`ignoreStealing`, `ignoreAssault`, `ignoreMurder`, `ignoreTrespass`) must be clear. A faction
with `doNotReportCrimesAgainstMembers` does not charge a crime against one of its members. The
bit names and values are from xEdit's `wbFACT` `DATA` flags ([factions](/formats/factions.md)).

## Witnesses

UESP: "If you are caught doing an illegal action by a witness you will incur a bounty ...
Successfully sneaking while committing a crime will prevent you from being detected." The
[perception pass](/engine/detection.md) already answers that every step. So crime does not compute
detection again. It takes the observer pairs that reached "detected", and drops dead observers.
A suspicious observer has not seen a crime. Charging on suspicion would make sneaking pay off at
random.

With no perception pass, the answer is "nobody saw". That is the safe side: an unseen theft still
marks the item.

The count moves either way. UESP: "Regardless of whether a crime is witnessed, the Statistics tab
on the menu keeps track of all your criminal activities". An unseen crime adds a count, no gold,
and a stolen mark.

The gold owed, the counts, and the stolen mark on goods are on the
[bounty ledger](/engine/bounty-ledger.md) page.

## Where crimes are reported

Each crime is reported in one call, and a world seam answers the rest: which cell a reference is
in, that cell's `XOWN`, its crime faction, and an item's value. Tests use a fake world.

| Crime | Reported at |
| --- | --- |
| Theft of a loose item | Taking the item, checked before it moves, because after that the reference is gone |
| Theft from a container | Taking from a container session |
| Assault | The one place every landed hit passes, which names both sides |
| Murder | The zero-health check, on the hit that killed the actor |
| Trespass | The world tick, when the player's cell changes |

Assault is the first hit on an actor that was not already hostile. UESP: "Self-defense against an
unprovoked assault is legal and not considered a crime". The session remembers which actors the
player hit first, so the second blow in the same fight is not a second crime.

The same set decides who is charged for a death. The zero-health check knows only that health hit
zero, not who caused it. Charging every death to the player would put a 1000 gold bounty on a
bandit killing a guard, on fall damage, and on a script's `Kill`. So only an actor the player hit
first is a murder victim. This also matches UESP: "if you kill an NPC ... after attacking them and
making them hostile, you can be simultaneously guilty of both assault and murder". A bandit that
attacked first is not a murder victim.

Melee, archery, and combat all report hits through one function, so a sword and an arrow cannot
disagree about what is a first strike.

## Not done yet

- There is no reporting chain. A witness charges the bounty the moment it sees the act. In the
  original, it walks to a guard and reports. Crimes by followers, animal witnesses, and children
  telling adults are the same shortcut.
- Trespass is charged on arrival, not after the warning and the 30 second grace period.
- Pickpocketing needs a sneak menu. `CRVA` already prices it at 25.
- A one-hit kill charges assault and murder. UESP says only murder. The hit is reported before the
  zero-health check notices the death.
- `doNotReportCrimesAgainstMembers` does not see an actor-owned reference. The flag checks the
  victim's memberships, which are stored per placed actor, but `XOWN` names a base record. A
  faction-owned reference works, because a faction counts as its own member.
- Crafting does not clear the stolen mark. UESP says an item fully used up in crafting loses it.
  There is no crafting yet.

## Controls

World > Crime & Factions:

- Bounty: the bounty per crime faction in its two halves, and what the faction's guards do. Add
  changes one half, Clear removes both.
- Theft: whether taking the crosshair target is theft, who owns it, and the player's stolen items.
- Memberships: the factions and ranks of the player and of an actor under the crosshair, what that
  actor thinks of the player, and each hostility term. Join and Leave change memberships.
- Vendor: see [vendor factions](/engine/vendor-factions.md).

`FACT`, `RELA`, and `ASTP` records are in Library > Asset Browser > Reference records.
