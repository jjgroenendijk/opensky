---
type: Subsystem
title: Container and barter menus
description: The two-pane container and barter menus - the vanilla price formula and its two
  game settings, transactions that move gold and items in one write, and the measured AS2
  contract of containermenu.swf and bartermenu.swf.
tags: [engine, ui, menu, swf, inventory, barter, scaleform]
---

# Container and barter menus

`containermenu.swf` and `bartermenu.swf` are two skins on one vanilla class. Both come from
`ItemMenu`, both import the same list parts as `inventorymenu.swf`, and both place their lists at
the same paths. So OpenSky drives both with one bridge, one two-pane list, and one set of
transactions. What differs is the price.

The row list is the [inventory menu](/engine/inventory-menu.md)'s. Container transfers are the
[interaction](/engine/interaction.md) container sessions. Merchants are on the
[vendor factions](/engine/vendor-factions.md) page.

## The price formula

From UESP "Skyrim:Speech", section "Prices" (<https://en.uesp.net/wiki/Skyrim:Speech#Prices>):

```text
price factor = fBarterMax - (fBarterMax - fBarterMin) * min(skill, 100) / 100
buy price    = round(value of item * buy price modifier * base price factor)
sell price   = round(value of item * sell price modifier / base price factor)
```

`fBarterMax` defaults to 3.3 and `fBarterMin` to 2.0. A skill above 100 has no effect. Two caps
apply: the sell price is at most `value * 1.00`, and the buy price is at least `value * 1.05`.
The same page lists results the code is tested against: a factor of 3.3 at Speech 0, 3.10 at 15,
and 2 at 100, and a sell factor of 0.322 at 15.

Choices on top of the formula:

- Both settings are read from the load order ([game settings](/formats/gmst.md)), so a plugin
  that changes barter changes OpenSky. Only a missing, non-finite, or non-positive setting falls
  back to the vanilla default. A zero factor would divide the sell price by zero, and a negative
  one would pay the player to buy. The panel shows which plugin each value came from.
- Speech is fixed at 15, the vanilla starting skill and the value UESP lists. It is a parameter,
  so reading the real skill later changes one call.
- The buy and sell modifiers are 1. They carry the Haggling and Allure perks and Fortify Barter,
  which are not applied yet.
- A stack is priced per item and then multiplied. Vanilla shows one price per row. Pricing the
  stack as a whole would round once instead of once per item, and disagree with the row.

At vanilla settings the caps never apply, because the factor stays between 2.0 and 3.3. They
apply once a plugin sets `fBarterMin` below 1.05.

On the local install both settings come from `Skyrim.esm`, and the factor at Speech 15 is 3.105.
An iron cuirass worth 125 costs 388 to buy and sells for 40.

## Transactions

A barter session is a live view of one merchant, not a copy. Stock and both purses are read again
on every access, like a container session.

Gold is not a separate field. It is a normal `Gold001` stack in the merchant's inventory. So a
merchant's purse and stock are one inventory, and buying moves a stack of gold the way it moves a
sword.

Every transaction is one exchange. It computes both owners' final inventories, with both moves
applied, before it writes either one. Two separate transfers would not be one operation: a sale
the merchant cannot pay for would hand over the item and then fail. Each transaction writes two
change log entries, one per owner, so it is saved like any other world change.

A refusal writes nothing:

| Error | When |
| --- | --- |
| `notStocked` | The player asks to buy more than the merchant has |
| `notCarried` | The player asks to sell more than they carry |
| `playerCannotAfford` | The price is more than the player's gold |
| `merchantCannotAfford` | The price is more than the merchant's gold |
| `nonPositiveCount` | A count of 0 or less. A caller bug, not a refusal |
| `priceOutOfRange` | The price is more than one gold stack can hold |
| `vendorClosed` | Outside the vendor's hours |
| `vendorDoesNotTrade` | The vendor's buy and sell list excludes the item |
| `vendorRefusesStolen` | The sale reaches stolen copies and the vendor is not a fence |

A merchant with no gold buys nothing and still sells everything. An item worth 0 still changes
hands: the gold part of the exchange is skipped, not refused.

## The two-pane list

Both movies show one item list at a time and switch which owner it shows. So the container menu
model is two inventory menu panes plus a side, not a new row type. This keeps the three menus in
agreement about what a row is, how rows sort, and how gold is split out.

The mode sets what choosing a row does, and the button label: Take and Store for a container,
Buy and Sell for a merchant. A row's price follows its side: the merchant's stock at the buy
price, the player's items at the sell price. So one item shows two prices, one on each side of
the counter. The affordability check asks the side that pays: the player when buying, the
merchant when selling.

Every transaction rebuilds both panes. The side and both selections carry over to the new model,
so the cursor does not jump to the top after each transfer. A selection whose row is gone is
dropped, not moved to whatever row took its place.

## The movie contract

Measured on the user's installed movies with `openskycli swf action-run --movie containermenu`
and `--movie bartermenu`. Both movies place `InventoryLists_mc`, `ItemCard_mc`, and
`BottomBar_mc` as imported characters, so they need the cross-movie import merge: 3 source movies,
675 characters, 3 placeholders bound, 0 unresolved for each ([SWF imports](/formats/swf-display-list.md#importassets-57-and-importassets2-71)).

| Thing | Path |
| --- | --- |
| Menu (`ContainerMenuObj` or `BarterMenuObj`) | `/Menu_mc` |
| Category list | `/Menu_mc/InventoryLists_mc/CategoriesListHolder/List_mc` |
| Item list | `/Menu_mc/InventoryLists_mc/ItemsListHolder/List_mc` |
| Player gold | `/Menu_mc/BottomBar_mc/PlayerInfoCard_mc/PlayerGoldValue` |
| Carry weight | `/Menu_mc/BottomBar_mc/PlayerInfoCard_mc/CarryWeightValue` |
| Merchant gold | `/Menu_mc/BottomBar_mc/PlayerInfoCard_mc/VendorGoldValue` |

The lists are the same `Shared.BSScrollingList` instances, with `EntriesA` and `iSelectedIndex`,
that the inventory menu fills. They are written the same way: rows, then `InvalidateListData`,
then the selection.

### The barter part

`BarterMenu` defines five properties on its menu instance. Read back after start-up:
`fBuyMult = 1.0`, `fSellMult = 1.0`, `iPlayerGold = 0.0`, `iVendorGold = 0.0`,
`iConfirmAmount = 0.0`. It also has `SetBarterMultipliers(afBuyMult, afSellMult)`. OpenSky sets
both multipliers from the price factor and writes both purses.

That the movie uses the multipliers to turn a row's `value` into the shown price is a guess from
the names, not measured. The engine's prices never come from the movie, so nothing depends on it.

`BottomBar.SetBarterInfo(aiPlayerGold, aiVendorGold, aiGoldDelta, astrVendorName)` moves the
player info card to its `Barter` frame. `VendorGoldValue` is placed by that frame and does not
exist before it. That is why the container movie has no vendor gold field at all. The gold delta
is 0: it is what a pending transaction would move, and nothing is ever pending, because the
quantity slider and the confirm step are not used.

### Engine calls

Each movie's constant pool gives its engine calls:

| Call | Movie |
| --- | --- |
| `CloseMenu`, `ItemSelect` | Both |
| `ItemTransfer`, `TakeAllItems`, `EquipItem` | `containermenu.swf` |
| `ShowRawDealWarning`, `GetRawDealWarningString` | `bartermenu.swf` |

`GetRawDealWarningString` returns the empty string. The only vanilla string behind a barter
warning is `sNotEnoughVendorGold`, "Transaction value: %d gold. Vendor only has %d gold.". That
warning belongs to the original's "sell for less" flow. OpenSky refuses such a sale
(`merchantCannotAfford`) instead, so the warning is never needed.

Measured on one full run of each movie at 1280x720, with a real two-sided inventory, one
navigation step, and one transaction from each side:

| Measure | `containermenu.swf` | `bartermenu.swf` |
| --- | --- | --- |
| Display nodes | 375 | 361 |
| Faults | 0 | 0 |
| Unimplemented opcodes | 0 | 0 |
| Unhandled bridge calls | 0 of 44 | 0 of 50 |

## Not done yet

- Every transfer and trade moves one item. The vanilla `QuantitySlider` is built but never
  driven, and neither is the `ShowConfirmMessage` step.
- There is no "sell for less". A sale the merchant cannot pay for is refused.
- Speech, perks, and Fortify Barter are fixed values.
- Category changes are made by the engine, as in the inventory menu, for the same measured
  reason.

## Controls

World > Container Menu has two sections:

- Merchant: choose any loaded container as the merchant, from a list or under the crosshair. A
  chosen container trades with no vendor rules.
- Container menu: open, close, up, down, switch side, transfer, take all, barter, and show the
  movie. Every button sends the same menu input as the keyboard.

To repeat a run without the test host:
`make run-cli ARGS="swf container-menu --mode barter --side player --down 2 --transfer 1"`.
Frames go to the gitignored `logs/` folder.
