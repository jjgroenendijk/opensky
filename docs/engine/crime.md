---
type: Subsystem
title: Crime and bounty
description: Ownership enforcement, the four crime events, witnessing through the perception
  pass, the per-crime-faction bounty ledger, and the stolen flag on inventory stacks.
tags: [engine, crime, factions, inventory, runtime-state]
timestamp: 2026-08-22T00:00:00Z
---

# Crime and bounty

Ownership was decoded for two milestones before anything read it. `PlacedReference` carried
`XOWN`/`XRNK`, `Container` carried the COED per-entry owner, and the M12 gate panel said
outright that it was "an inspection, not a gate". This is the gate: a take that reaches
somebody else's property is theft, theft that somebody sees costs gold, and the goods stay
marked whether or not anybody saw.

## Contents

- Ownership
- Which faction answers for a place
- The four crimes and what they cost
- Witnessing
- The bounty ledger
- Stolen goods
- Where the hooks sit
- Condition function and Papyrus natives
- Persistence
- Verification surface
- v1 limitations

## Ownership

`OwnershipResolver` answers one question: does this actor own, or may it freely use, that
reference?

**Precedence.** A reference's own `XOWN` wins. A reference without one inherits the owner of
the cell it stands in, and a cell with no `XOWN` either is nobody's. The order is a *first
match* rather than a merge: a chest inside an owned shop that names its own owner is that
owner's, and the shop's claim does not also apply.

The inheritance is what the data actually needs. UESP states it from the player's side — "an
item's name that appears in red text means that the item is owned and picking it up is
stealing" ([Skyrim:Crime](https://en.uesp.net/wiki/Skyrim:Crime)) — and every crate in
Belethor's shop reads as owned while carrying no `XOWN` of its own. Observed on this install
with `openskycli record`: `WhiterunBelethorsGeneralGoods` carries one `XOWN` field and
Breezehome, the house the player buys, carries none. CELL `XOWN` and `XRNK` were not decoded
before this item; `Cell` decodes both now, and `CellScene` carries them so a resident cell
can be asked without re-reading the record.

**What an owner may be.** `XOWN` names either an NPC_ or a FACT and nothing in the field says
which, so the resolution is by lookup: a link the load order carries a FACT for is a faction
owner, and anything else is an actor owner. That ordering matters — asking the faction store
first is the only way to tell the two apart without decoding the target record. A link
nothing resolves is deliberately still an actor owner rather than "unowned": reading a
dangling owner as free would make a shop lootable the moment a plugin went missing.

**Who may use it.** An actor owner matches on the NPC_ base, because that is what `XOWN`
names: every ACHR placed from the owning base is the owner, and the player — who has no base
record in this engine — matches none of them. A faction owner matches a member at or above
the rank `XRNK` demands; an absent `XRNK` reads as rank 0, the lowest rank vanilla authors,
so an ordinary member may use the property. A negative rank, which vanilla writes to mean "a
member the rank titles do not name", does not clear a rank-0 requirement.

The verdict is one of three: `unowned`, `permitted`, `forbidden`. Only `forbidden` is theft.

## Which faction answers for a place

A cell names its location with `XLCN`, a location names its crime faction with `FNAM`, and
almost no location names one — the link is authored at the hold and everything inside it
inherits by walking `PNAM` upwards. Observed on this install, which is what fixed the rule:

```text
WhiterunBelethorsGeneralGoodsLocation  PNAM -> WhiterunLocation      (no FNAM)
WhiterunLocation                       PNAM -> WhiterunHoldLocation  (no FNAM)
WhiterunHoldLocation                   FNAM -> CrimeFactionWhiterun
```

`CrimeFactionResolver` walks that chain through `LocationStore.parentChain(of:)`, which
already bounds a malformed `PNAM` cycle with a visited set, and the first `FNAM` found wins.
UESP describes the same shape from the player's side: "Bounties are tracked separately for
each of Skyrim's nine holds and you will only incur a bounty in the hold in which you commit
a crime."

A chain that ends without an `FNAM` has no crime faction, and that is a real answer rather
than a gap: a dungeon and a stretch of road belong to nobody, which is why killing a bandit
on the road costs nothing. Nothing substitutes a default faction. A location that authors a
*dangling* `FNAM` stops the walk anyway — skipping past it to a grandparent would charge the
bounty to the wrong hold.

## The four crimes and what they cost

`CrimeKind` has four cases: theft, assault, murder and trespass. They are the four the FACT
`CRVA` struct prices and the four this engine can observe happening; an enum case nothing can
raise is a promise the engine does not keep.

**The numbers come from the record, never from a game setting.** That is not a
simplification. `openskycli gmst list --prefix iCrime` on this install reports exactly two
settings — `iCrimeGoldStealHorse` (100) and `iCrimeGoldWerewolf` (1000) — and neither prices
any of these four. `CrimeFactionWhiterun`'s `CRVA` reads "murder 1000, assault 40, trespass
5, pickpocket 25, steal multiplier 0.5000, escape 100, werewolf 1000", and UESP's bounty
table gives the same four numbers from the player's side.

| Crime | Amount | Source |
| --- | --- | --- |
| Theft | item value x steal multiplier, rounded down | `CRVA` + "Half of the stolen item's value, rounded down" |
| Assault | `CRVA` assault (40 in Whiterun) | `CRVA` + UESP "Assault ... 40" |
| Murder | `CRVA` murder (1000) | `CRVA` + UESP "Murder ... 1000" |
| Trespass | `CRVA` trespass (5) | `CRVA` + UESP "Trespassing ... 5" |

Rounding down is what makes a one-gold trinket free; nothing invents a floor. A `CRVA` too
short to carry a steal multiplier — the field arrived in a later record version — reads as
the neutral multiplier of 1, so a plugin writing a 12-byte `CRVA` charges the item's full
value rather than nothing. Zero was the alternative and is the damaging one: it would make
every theft from such a faction free.

A faction with no `CRVA` at all prices nothing, and the crime is still counted.

**Faction flags gate the charge.** `trackCrime` has to be set, the per-kind ignore bit
(`ignoreStealing`, `ignoreAssault`, `ignoreMurder`, `ignoreTrespass`) must not be, and a
faction with `doNotReportCrimesAgainstMembers` refuses a crime whose victim belongs to it.
Bit names and values are xEdit's `wbFACT` DATA flags, which UESP's FACT page spells
identically; see [factions](/formats/factions.md).

## Witnessing

"If you are caught doing an illegal action by a witness you will incur a bounty ...
Successfully sneaking while committing a crime will prevent you from being detected." That is
exactly the question the [perception pass](/engine/detection.md) already answers every fixed
step, so nothing here recomputes detection: `PerceptionCrimeWitnesses` reads the pairs the
pass has converged, keeps the ones that reached `detected`, and drops observers the session
knows are dead. Detection only — an observer that is merely suspicious has not seen a crime,
and crediting a bounty on a suspicion would make sneaking pay off at random.

The seam is a protocol, `CrimeWitnessSource`, for the reason the crime term on
`HostilityDerivation` is one: the crime runtime has to be testable without a perception pass,
and a synthetic scene has no observers at all. A session with no pass answers "nobody saw",
which is the safe direction: an unwitnessed theft still marks the item, so nothing is
silently lost.

The count moves either way. "Regardless of whether a crime is witnessed, the Statistics tab
on the menu keeps track of all your criminal activities" — so an unwitnessed crime leaves a
count, no gold, and a marked stack.

## The bounty ledger

`CrimeLedgerState` is a world-state component keyed by the perpetrator, holding one row per
crime faction: the gold owed and the four crime counts. A slot of its own beside `factions`
and `playerProgress` for the lifetime reason those two are separate from `actorValues` — a
bounty moves when a crime is witnessed, while the values beside it are rewritten sixty times
a second.

Per faction rather than per hold, because a hold is not a concept this engine has and a crime
faction is. The twelve independent bounties UESP names — nine holds, the Companions, the
Tribal Orc strongholds and Raven Rock — are twelve crime factions, so keying by faction is
the general shape and the vanilla one at once, and it is what a `Faction.GetCrimeGold` call
asks for.

Counts travel beside the gold because they are not derivable from it: an unwitnessed crime
moves one and not the other.

Rows are normalized on the way in — sorted by faction key, empty rows dropped, a repeated
faction collapsed to its last row — so the save writes the same bytes twice for the same
state. A faction this load order no longer resolves is *kept*, the rule a stored membership
and an owned perk follow: a bounty is progress the player made, and losing it because a
plugin came and went is the damaging direction to fail in. The whole component is dropped
once it says nothing.

`modifyCrimeGold` and `setCrimeGold` move the gold and leave the counts alone: paying a fine
settles the debt and does not un-commit the crime. Gold is clamped at zero — a bounty is paid
down to nothing, never past it.

## Stolen goods

"Stolen items in your inventory will be marked with the word 'Stolen', even if you were able
to steal the item without being detected. As long as this tag is present, the item is
considered stolen."

So the flag follows the goods rather than the bounty, and it is part of the *stack key*
rather than a property of the item: "Should you steal multiple items of the same type, each
item considered stolen is tracked separately when dropped." Ten honest arrows and one stolen
arrow are two `InventoryStack`s of the same base, ordered honest first so the bytes stay a
pure function of the state.

- `count(of:)` still answers the total across both, because that is what every question
  predating crime means by "how many do I have".
- `count(of:stolen:)` and `stolenCount(of:)` answer one flavour.
- Removing spends honest copies first, so an inventory holding both parts with the ones that
  carry no consequence.
- `split(taking:of:)` says how a removal divides, and `adding(_:split:owner:)` puts the same
  division down on the other side — which is what makes a transfer carry the split with it.
- `markingStolen(_:count:)` re-marks goods already in hand, which is what a take out of an
  owned container is.

Both item lists show one row per *item* rather than per stack, with the stolen count beside
it: two rows sharing a name and a FormID would be two identical-looking controls acting on
the same items, and `removing` spends honest copies first regardless of which the player
clicked. The inventory row reads `[stolen]` when the whole row is hot and `[n stolen]` when
only part of it is.

A barter carries each leg's own split, so selling hot goods hands the merchant hot goods and
the gold that comes back is honest — the difference issue #506's fence rules will read.

## Where the hooks sit

Every crime goes through `CrimeReporter`, which turns "this happened" into a `CrimeEvent`
using `CrimeWorld` — the seam that answers which reference stands in which cell, what that
cell's `XOWN` says, which crime faction answers for it, and what an item is worth. The split
is the shape `MeleeCombatWorld` and `PerceptionWorld` already take: the hooks say what
happened in one call, and the assembly is testable against a fake world rather than a
streamed cell.

| Crime | Hook |
| --- | --- |
| Theft (loose item) | `WorldItemRuntime.take` — asked before the item moves, because once it is in the inventory the reference is gone |
| Theft (container) | `ContainerSession.take`, through `InventoryRuntime.transfer(markingStolen:)` |
| Assault | `reportScriptHit`, the one seam every landed blow passes through and the only one that names both sides |
| Murder | the zero-health sweep, on the call that actually killed the actor |
| Trespass | the world tick, when the cell the player stands in changes |

Assault is the *first* strike against an actor that was not already hostile — "Self-defense
against an unprovoked assault is legal and not considered a crime" — so the session remembers
which actors the player struck first and the second blow of the same fight is not a second
crime.

That same set is how a death is **attributed**, not merely refined. The zero-health sweep
that notices a death knows only that health reached zero, not who emptied it, so charging
every non-hostile death to the player would put a 1000-gold bounty on a bandit killing a
guard, on fall damage, and on a script's `Kill`. Only an actor this player struck first
becomes a murder victim — which also gets the interesting half of the rule right: "if you
kill an NPC ... after attacking them and making them hostile, you can be simultaneously
guilty of both assault and murder", so an actor the player assaulted is still a murder victim
even though it died angry, while a bandit that attacked first is not.

Assault happening at `reportScriptHit` is deliberate: melee, archery and the combat loop all
report through that one implementation, so a sword swing and an arrow cannot disagree about
what counts as a first strike.

## Condition function and Papyrus natives

One condition function, from xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`:

```text
(Index: 459; Name: 'GetCrimeGold'; ParamType1: ptFactionNull)
```

The Creation Kit spells it 4555. `ptFactionNull` is nullable by declaration, and a null
parameter asks about the hold the subject is standing in rather than about no faction at all;
`CrimeConditionResolution.currentCrimeFaction` is what the caller fills from
`CrimeFactionResolver`. A session with no FACT data, a parameter naming a faction no plugin
defines, or a null parameter outside any hold all report `unavailableCrime` rather than
answering zero — see [conditions](/formats/conditions.md).

Five natives, each signature quoted from the Creation Kit wiki at its registration site:

| Native | Signature |
| --- | --- |
| `Faction.GetCrimeGold` | `int Function GetCrimeGold() native` |
| `Faction.ModCrimeGold` | `Function ModCrimeGold(int aiAmount, bool abViolent = False) native` |
| `Faction.SetCrimeGold` | `Function SetCrimeGold(int aiGold) native` |
| `Actor.SendAssaultAlarm` | `Function SendAssaultAlarm() native` |
| `Actor.SendTrespassAlarm` | `Function SendTrespassAlarm(Actor akCriminal) native` |

Both alarms are credited as witnessed outright rather than run past the perception pass: the
script is asserting that this actor caught the criminal — "have this actor pretend he caught
the specified criminal" — so asking the detection state whether it really did would let a
scripted alarm fail silently because the witness happened to be facing away. The wiki also
notes the trespass alarm "will not result in the 'time to go' dialogue that precedes the
crime", which is why nothing warns first.

## Persistence

Two additive chunks in [the OpenSky save container](/formats/opensky-save.md):

- **`CRIM`** — one entry per actor with a ledger, and inside it one row per faction with the
  gold and the four counts in `CrimeKind.allCases` order.
- **`STOL`** — for every owner holding stolen goods, one row per item saying how many of its
  copies are stolen.

`STOL` is a sibling of `INVN` rather than an extension of it, for the reason `QALS` is a
sibling of `QSTS`: `INVN` entries are a flat positional layout with no per-entry length, so
appending a flag to each stack would make every older build misparse the *whole* chunk
instead of skipping the new part. `INVN` therefore keeps writing one row per item with honest
and stolen copies summed — an older build restores a complete inventory that has simply
forgotten which copies were stolen — and `STOL` carries the split. It is merged after `INVN`
for the same reason: the split can only be applied once the totals are in place.

A law-abiding session writes neither chunk, so its bytes match what the encoder produced
before either existed.

## Verification surface

`World > Inventory & Equipment` already reported ownership under the crosshair and said no
crime system enforced it. It now states the enforced verdict instead: whether taking the
reference would be theft for the player *right now* — which accounts for the cell's `XOWN`
and the player's memberships, not just the reference's own field — and what the bounty would
be if witnessed. The crime and faction sidebar destination proper is issue #507.

## v1 limitations

Recorded here rather than pretended away:

- **No reporting chain.** A witness credits the bounty the moment it sees the act. In the
  original it walks to a guard and tells them, which is a package, a travel path and a
  conversation. Follower-committed crimes, animal witnesses and the child-tells-an-adult
  chain are the same simplification from the other side.
- **Trespass is recorded on arrival**, not after the warning and the 30-second grace the
  original gives. The warning is a guard line and a timer, both of which are issue #505's.
- **No violent/non-violent split.** The ledger holds one bounty per faction, so
  `GetCrimeGoldViolent`, `GetCrimeGoldNonViolent` and `SetCrimeGoldViolent` are not
  installed, and `ModCrimeGold`'s declared `abViolent` flag is accepted and ignored.
  Answering a violent-only question from a combined total would be a convincing wrong number
  rather than a measurable gap; the unimplemented condition indices are counted by
  `ConditionTally` and the unimplemented natives by `PapyrusNativeLog`, which is what ranks
  the next one to build.
- **Pickpocketing and jail time served are deferred.** Both need machinery this milestone
  does not build — a sneak menu and a time skip. `CRVA` prices pickpocketing at 25 and the
  load order carries `iCrimeGoldStealHorse` and `iCrimeGoldWerewolf`, so the numbers are
  already in hand when the mechanisms arrive.
- **A one-hit kill charges assault as well as murder.** UESP records that it should charge
  only the latter, but the blow is reported at `reportScriptHit` and the death is noticed by
  the next zero-health sweep, so the assault is already on the ledger by the time the murder
  arrives.
- **`doNotReportCrimesAgainstMembers` cannot see an NPC_-owned reference.** The flag is
  checked against the victim's stored memberships, and a theft's victim is the owner `XOWN`
  names — a base record, while `ActorFactionState` is keyed by a placement. A faction-owned
  reference is covered, because a faction is trivially its own member; an actor-owned one is
  not.
- **No guard response.** Confrontation, arrest, bounty payment and attack-on-sight are issue
  #505; the `CrimeHostilitySource` seam on `HostilityDerivation` is where they will join.
- **Fences and stolen-goods barter rules** are issue #506; this item provides the flag they
  read.
- **Crafting does not clear the flag.** UESP records that anything completely consumed in
  crafting loses its stolen status; this engine has no crafting yet.
