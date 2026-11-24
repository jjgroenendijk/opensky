---
type: Subsystem
title: Vendor factions
description: How an actor becomes a merchant through a vendor faction - its chest, hours,
  buy and sell list, fences and stolen goods, and barter opened from dialogue.
tags: [engine, inventory, barter, factions]
---

# Vendor factions

A merchant is an actor with a vendor faction among its faction memberships. The faction's vendor
block says where it sells from, when, and what. The source for every rule is the Creation Kit
wiki's Faction page, Vendor tab (<https://ck.uesp.net/wiki/Faction>). The record fields are on
the [factions](/formats/factions.md) page. The menus are on the
[container and barter menus](/engine/barter.md) page.

| Field | Meaning |
| --- | --- |
| Vendor flag (`DATA` `0x4000`) | Marks a vendor faction in the editor. The game does not read it when it picks the vendor faction (see below) |
| `VENC` | The merchant chest the vendor sells from. With none, the vendor's own inventory |
| `VENV` start and end hour | Trade opens at the start hour and closes at the end hour |
| `VEND` | A keyword `FLST`, flattened through nested lists. The vendor trades items with one of them |
| `VENV` "Not Buy/Sell" | Turns the list around: the vendor trades what does not match |
| `VENV` "Only Buys Stolen Goods" | The vendor is a fence |

The Creation Kit gives an example: "The pawnbroker Belethor in Whiterun uses VendorItemsMisc as
the buy/sell list, and has this checked". So he trades everything except keys and items marked
not sellable. On the local install `ServicesWhiterunBelethorsGoods` has exactly that, with hours
8 to 20 and the merchant chest `skyrim.esm:09CAF9`.

## Hours

Both hours are strict: a faction trades when `start < hour < end`, with the hour as a fraction
from 0 to 24. With `8-20`, the shop is closed at exactly 8:00, opens just after, and closes again
at exactly 20:00. Hours never wrap past midnight: a start equal to or after the end is no window,
so that faction never trades. A faction with no `VENV` reads as `0-0` and never trades. `0-24` is
open at every hour except exactly midnight.

On the local install there are 145 vendor factions. 81 are open `0-24` and 41 are open `8-20`.
One has `0-0`. The Creation Kit's "Creating a Merchant" page agrees: "If you don't add a start
and end time, the merchant wont offer services". At 3am a vendor open `8-20` refuses.

## Place and conditions

A vendor also trades only where its `PLVD` rule puts it, and only while its `CITC` and `CTDA`
conditions hold. The conditions run with the vendor as both the subject and the target. A faction
with no `PLVD` never trades. The place types are UESP's FACT page. Distances are in game units,
measured in all three axes, and a distance equal to the radius still passes.

| `PLVD` type | Rule |
| --- | --- |
| 0 | Within the `VENV` radius of a placed reference. The reference must be found, enabled, and in the vendor's cell or worldspace |
| 1 | Inside one cell. The radius is not read |
| 2 | Near where the vendor's current package starts, within the radius but at least 100 units |
| 3 | Near the vendor's editor location, within the radius but at least 100 units |
| 6 | Within the radius of the reference the vendor links to with a keyword. No link fails |
| 12 | Anywhere |
| any other | Never |

For types 2 and 3, a vendor in an interior must be in the same cell as the point, and a vendor
outdoors must be in the same worldspace. For types 0 and 6 a radius of 0 has no minimum, so the
vendor would have to stand on the point. Vanilla vendors that author 0 use type 1, which reads no
radius.

The vendor flag (`DATA` `0x4000`) is not read here. A faction that keeps `VENV` and `PLVD` data
after its vendor flag was cleared still makes a vendor, as the Creation Kit's Faction page warns.

An actor's factions are walked in order: first those on its base record, skipping rank -1, then
the ones added while the game runs, in the order they were added. A faction removed while the game
runs leaves the walk. The first faction whose hours, conditions, and place hold is the vendor
faction, and the walk stops there.

## Offers services

The condition function `GetOffersServicesNow` is 1 when the actor has a vendor faction now, by the
walk above, and that faction has a `VEND` buy and sell list. It is 0 for any other subject and
for an actor with no vendor faction. When the first faction that holds has no list, the result is
0 and no later faction is tried. The running package's "Offers Services" flag is not read: an
apothecary whose shop package has the flag clear still offers services during her shop hours.
Day of the week, combat, dialogue, and death are not read, unless the faction's own conditions
test them.

The game keeps the chosen faction on the actor and computes it again at most every 20 seconds of
unpaused real time. The condition function only tries again while no faction is stored, so a
vendor can still offer services just after closing time, until another check, such as the
barter item check, computes it again.

### In OpenSky

OpenSky computes the vendor faction each time and keeps nothing between checks. It cannot place
the start of a package, so a type 2 rule passes. It does not compare the cell or worldspace of a
type 3 point. When no faction holds, a barter refusal names the reason of the first one.

## Restocking

A merchant chest restocks `iDaysToRespawnVendor` game days (2) after it was last stocked. The
check runs when the vendor's barter opens: a due chest drops its runtime inventory and tempering,
so it reads its leveled `CNTO` list again. The time each chest was stocked is the
`vendorRestock` world-state component, which a save stores in the `VRST` chunk
([world chunks](/formats/opensky-save-world-chunks.md)).

## Stock, gold, and what a vendor takes in the game

- The vendor's side of the barter menu is the merchant's own inventory and the `VENC` chest
  together. The vendor's gold is the gold in both, so it refills when the chest restocks.
- When the vendor cannot pay, the menu shows `sNotEnoughVendorGold` ("Vendor only has %d gold.").
- A restock resets the chest to its listed items and gold. Items the player sold to it go.
- The vendor's own side is filtered by the same `VEND` check as the player's, so it lists only
  what it trades.

What the vendor buys from the player:

1. Never a key, and never a quest item.
2. A vendor with no vendor faction buys anything.
3. Otherwise an item must have a keyword in the `VEND` list, or lack all of them under "Not
   Buy/Sell".
4. The player's `BypassVendorKeywordCheck` actor value (94) skips step 3. The Merchant perk sets it
   through its ability.
5. A stolen copy is left out, unless the faction has "Only Buys Stolen Goods", or the player's
   `BypassVendorStolenCheck` actor value (93) is not zero.

OpenSky follows these rules. A buy takes the chest's copies first, then the vendor's own; a sale
puts the item in the chest and pays from the chest's gold first, then the vendor's own. The
vendor's own side leaves out what it wears.

Investor is not a rule of the barter menu. It is a quest stage the perk sets, and the dialogue and
scripts do the rest.

## Investment and trainers

Neither is part of the vendor faction. Both come from the load order:

- The Speech perk Investor carries a quest-stage perk effect. Adding the perk sets that stage, and
  the dialogue it starts calls the investment scripts. Master Trader works the same way.
- Trainers are dialogue that calls `Game.ShowTrainingMenu` ([training](/engine/training.md)).

## The list

A vendor sells from its chest only what matches its list. The Creation Kit: "a vendor will not
sell items in this container unless they also match the vendor's buy/sell list". The same test
limits what it buys. One faction on the local install, `WhiterunBanneredMareFaction`, has no
list. OpenSky reads that as no keyword limit.

## Fences

The flag's name says "only", and the Creation Kit says it sets "this vendor up to only pay for
stolen items the player wants to fence". OpenSky reads it as "also buys stolen goods". Reasons:

- UESP's Merchants page (<https://en.uesp.net/wiki/Skyrim:Merchants>) lists fences as the
  merchants that "are the only merchants who will purchase stolen goods".
- All nine fence factions on the local install, `ServicesThievesGuildTonilia` among them, also
  have Belethor's inverted `VendorItemsMisc` list. That list would have no use on a vendor that
  bought nothing honest.

A vendor that is not a fence refuses a sale that would reach stolen copies. Honest copies are
sold first, so a player with both kinds can still sell the honest ones.

A fence takes stolen goods in as honest ones. A vendor's goods also reach the buyer as honest
ones. UESP: "Purchasing stolen items you place in there will remove their stolen tags". A
container chosen by hand as a merchant keeps each item's stolen state.

## The chest

Most merchant chests are in the shop's own interior. Of the 116 `VENC` references on the local
install, 91 are in interior cells. So a player trading in person mostly has the chest loaded. A
chest in a cell that is not loaded trades from its plugin placement: its stock comes from its base
container, and it restocks on the same clock as a loaded one.

## Barter from dialogue

The merchant topics in the load order run a script fragment that calls `Actor.ShowBarterMenu` on
the speaker. On the local install, 32 of the 39 scripted `INFO` records with a
`JobMerchantFaction` condition do this. The native function opens the barter menu with the
speaker's vendor, so dialogue needs no extra code for barter.

The Creation Kit says the original shows an empty menu for an actor that is not loaded, or whose
merchant conditions fail. OpenSky refuses instead, and says why.
