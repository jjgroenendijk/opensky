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
| Vendor flag (`DATA` `0x4000`) | Makes a membership a vendor faction. The first one in membership order wins |
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

The start hour is included and the end hour is not. An end of 24 or more runs to midnight. A
start after the end wraps past midnight.

On the local install there are 145 vendor factions. 81 are open `0-24` and 41 are open `8-20`.
One has `0-0`. The Creation Kit's "Creating a Merchant" page: "If you don't add a start and end
time, the merchant wont offer services". So `0-0` is no window, and that vendor never trades. At
3am a vendor open `8-20` refuses too.

## Place and conditions

A vendor also trades only where its `PLVD` rule puts it, within the `VENV` radius, and only while
its `CITC` and `CTDA` conditions hold. The place types are UESP's FACT page:

| `PLVD` type | Rule |
| --- | --- |
| 0 | Near a placed reference |
| 1 | Inside one cell |
| 2 | Near where the vendor's current package starts |
| 3 | Near the vendor's editor location |
| 6 | Near the reference the vendor links to with a keyword |
| 12 | Anywhere |

A radius of 0 sets no distance limit. Vanilla vendors author 0 and still trade, so 0 cannot mean
"on the exact spot". A type OpenSky does not read, such as an alias, never refuses.

An actor in two vendor factions trades as the first one whose hours, place, and conditions hold.
When none holds, the refusal names the first one's reason.

## Restocking

A merchant chest restocks `iDaysToRespawnVendor` game days (2) after it was last stocked. The
check runs when the vendor's barter opens: a due chest drops its runtime inventory and tempering,
so it reads its leveled `CNTO` list again. The time each chest was stocked is the
`vendorRestock` world-state component, which a save stores in the `VRST` chunk
([world chunks](/formats/opensky-save-world-chunks.md)).

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
install, 91 are in interior cells. So a player trading in person has the chest loaded. A chest
that is not loaded is refused with a reason. It is not read as empty, because its stock is a
leveled list, and an empty shop would look like a vendor with nothing to sell.

## Barter from dialogue

The merchant topics in the load order run a script fragment that calls `Actor.ShowBarterMenu` on
the speaker. On the local install, 32 of the 39 scripted `INFO` records with a
`JobMerchantFaction` condition do this. The native function opens the barter menu with the
speaker's vendor, so dialogue needs no extra code for barter.

The Creation Kit says the original shows an empty menu for an actor that is not loaded, or whose
merchant conditions fail. OpenSky refuses instead, and says why.

## Not done yet

- A merchant chest that is not loaded cannot be traded from, and so it cannot restock either.

## Controls

World > Crime & Factions > Vendor shows the chosen actor's vendor faction, chest, hours, list,
and fence flag. It can choose another vendor faction, open the barter menu, and Restock all makes
every merchant chest due.
