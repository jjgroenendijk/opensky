---
type: Subsystem
title: Container and barter menus
description: The two-pane container transfer menu and the merchant barter menu - the vanilla
  price formula and the two GMSTs behind it, the merchant nomination seam, and the measured
  AS2 contract of containermenu.swf and bartermenu.swf.
tags: [engine, ui, menu, swf, inventory, barter, scaleform]
timestamp: 2026-08-02T00:00:00Z
---

# Container and barter menus

Milestone 12.2.3. The third and fourth menus OpenSky opens, and the first that moves gold.
They share one bridge, one two-pane list and one set of transactions, because
`containermenu.swf` and `bartermenu.swf` are two skins on one vanilla class: both derive
from `ItemMenu`, both import the same list components `inventorymenu.swf` imports, and both
address their lists at the same instance paths. What differs is the price.

Everything below the presentation layer reuses what earlier milestones built: the row list
is [inventory menu](/engine/inventory-menu.md)'s, the transfers are
[interaction](/engine/interaction.md)'s container sessions, and the accounting is
[runtime state](/engine/runtime-state.md)'s.

## Contents

- [The price formula](#the-price-formula)
- [Transactions](#transactions)
- [The two-pane list](#the-two-pane-list)
- [The merchant seam](#the-merchant-seam)
- [The vanilla data contract](#the-vanilla-data-contract)
- [Verification](#verification)
- [Limits / next](#limits--next)

| Layer | File | Target |
|---|---|---|
| Price formula | `opensky/Inventory/BarterPricing.swift` | app + CLI |
| Transactions | `opensky/Inventory/BarterSession.swift` | app + CLI |
| Two-pane list | `opensky/UI/ContainerMenuModel.swift` | app + CLI |
| Vanilla movie contract | `opensky/UI/ContainerMenuMovieBridge*.swift` | app + CLI |
| Panel seam | `opensky/ContainerMenuControlProviding.swift` | app + CLI |
| Renderer + AppKit wiring | `opensky/GameViewControllerContainerMenu*.swift` | app |
| Verification surface | `opensky/ContainerMenuPanelViewController.swift` and `opensky/Shell/Sections/ContainerMenu*.swift` | app |

## The price formula

Cited, not remembered. UESP "Skyrim:Speech", section "Prices"
(<https://en.uesp.net/wiki/Skyrim:Speech#Prices>) gives it as:

```text
price factor = fBarterMax - (fBarterMax - fBarterMin) * min(skill, 100) / 100
buy price    = round(value of item * buy price modifier * base price factor)
sell price   = round(value of item * sell price modifier / base price factor)
```

with `fBarterMax` defaulting to 3.3 and `fBarterMin` to 2.0, skill levels over 100 having
no effect, and two trade price caps: `max sell price = value * 1.00`,
`min buy price = value * 1.05`. The same page tabulates the results the implementation is
tested against — 3.3 buying at 0 Speech, 3.10 at 15, 2 at 100, and 0.322 selling at 15.

Four decisions sit on top of that formula:

- **Both settings are read out of the load order**, through
  [`GameSettingStore`](/formats/gmst.md), so a plugin that retunes barter retunes OpenSky.
  Only an absent, non-finite or non-positive setting falls back to the documented vanilla
  default — a zero factor would divide the sell price by zero and a negative one would pay
  the player to buy. `BarterPricing.source` names which plugin each value came from, and
  the sidebar prints it.
- **Speech is fixed at 15**, the vanilla starting skill and the value the source tabulates.
  Skill progression is M18+; `speechSkill` is a parameter rather than a constant so that
  milestone changes one call site.
- **The two price modifiers are 1.** They carry the Haggling and Allure perks and any
  Fortify Barter effect, all of which are out of scope, so `buyModifier` and `sellModifier`
  exist as a named seam rather than as a value this milestone computes.
- **A stack is priced per unit and multiplied.** Vanilla shows one row one price; pricing
  the stack whole would round once instead of `count` times and disagree with the row the
  player is reading.

The caps are dead weight at vanilla settings — the factor never leaves 2.0 to 3.3 — and
become live the moment a plugin lowers `fBarterMin` below 1.05. They are implemented and
tested through exactly that path.

Measured against the local install: `fBarterMin` and `fBarterMax` both resolve from
`Skyrim.esm`, giving a factor of 3.105 at Speech 15. An iron cuirass worth 125 costs 388 to
buy and fetches 40 to sell.

## Transactions

`BarterSession` is a live handle on one merchant, not a snapshot: stock and both purses are
read through `InventoryRuntime` every time they are asked for, the same never-cache rule
`ContainerSession` follows.

**Gold is not a currency field.** It is an ordinary `Gold001` stack in the merchant's own
inventory, so a merchant's purse and its stock are the same inventory, and buying moves a
stack of gold the way buying a sword moves a sword.

Every transaction is one `InventoryRuntime.exchange`, added by this milestone beside
`transfer`: it computes both owners' final inventories with both movements applied before
writing either. Two `transfer` calls would not be one operation — a sale the merchant could
not pay for would hand the item over and then fail. Because both writes go through
`WorldStateStore`, each transaction leaves two journal entries, one per owner, and
therefore lands in the save exactly like a script's `Disable()` does.

Refusals are ordinary outcomes rather than faults, and every one of them writes nothing:

| `BarterError` | When |
|---|---|
| `notStocked` | the player asked to buy more than the merchant holds |
| `notCarried` | the player asked to sell more than they carry |
| `playerCannotAfford` | the price exceeds the player's gold |
| `merchantCannotAfford` | the price exceeds the merchant's purse |
| `nonPositiveCount` | a count of zero or less, which is a caller bug rather than a refusal |
| `priceOutOfRange` | the price exceeds what one gold stack can hold |

**A merchant with no gold buys nothing and still sells everything**, which is the named
case in the milestone scope and a test of its own. A zero-price item still changes hands:
the zero-gold leg of the exchange is skipped rather than rejected, because a worthless item
is still tradeable.

## The two-pane list

Both movies present one item list at a time and swap which owner it belongs to, so
`ContainerMenuModel` is two `InventoryMenuModel` panes plus a side, not a new row type.
Reusing #289's list is what keeps the three menus agreeing about what an item row is, how
rows sort, and how gold is split out of them.

The mode picks what activating a row means and what the button says: `Take` / `Store` for a
container, `Buy` / `Sell` for a merchant. The price of a row follows the side it is
displayed on — the merchant's stock at the buy price, the player's at the sell price — so
the same item shows two numbers depending on which side of the counter it is on.
`canAffordSelection` asks the paying side, which is the player when buying and the merchant
when selling.

Every transaction rebuilds both panes from the store, and `restore(from:)` carries the side
and both selections onto the rebuilt model. Without it the cursor would jump back to the
top after each transfer. A selection whose row no longer exists — the one that just moved —
is dropped by the bounds check rather than silently pointing at whatever took its place.

## The merchant seam

There is no merchant system. Vanilla merchants sell from a faction-linked chest, and none
of that VENDR-style faction data is decoded, so this milestone's merchant is a container
reference a developer nominates. `ContainerMenuControlProviding` is the seam that
nomination goes through, and a faction-driven answer replaces it later without the menu
changing:

- `containerMenuMerchantOptions` lists every resident container by name, item count and
  purse, from `CellStreamer.containerInteractions()`.
- `selectContainerMenuMerchant(_:)` nominates one by reference.
- `selectContainerMenuMerchantFromInteraction()` nominates whatever the crosshair is on,
  which is the path a developer standing in front of a chest actually uses.

A nomination resolves to the same `InventoryHolder` `WorldItemRuntime.openContainer` builds
— reference key, CONT base, cell — so a chest opened from the crosshair and one nominated
from the sidebar are the same owner. A reference nothing resident resolves is refused
rather than given a fabricated key.

## The vanilla data contract

Measured paths, read back off the user's own installed movies with
`openskycli swf action-run --movie containermenu` and `--movie bartermenu`. Both movies
place `InventoryLists_mc`, `ItemCard_mc` and `BottomBar_mc` as imported characters, so all
of this depends on the cross-movie import merge #289 built: 3 source movies, 675
characters, 3 placeholders bound, 0 unresolved for each.

| Thing | Path |
|---|---|
| Menu (`ContainerMenuObj` / `BarterMenuObj`) | `/Menu_mc` |
| Category list | `/Menu_mc/InventoryLists_mc/CategoriesListHolder/List_mc` |
| Item list | `/Menu_mc/InventoryLists_mc/ItemsListHolder/List_mc` |
| Player gold | `/Menu_mc/BottomBar_mc/PlayerInfoCard_mc/PlayerGoldValue` |
| Carry weight | `/Menu_mc/BottomBar_mc/PlayerInfoCard_mc/CarryWeightValue` |
| Merchant purse | `/Menu_mc/BottomBar_mc/PlayerInfoCard_mc/VendorGoldValue` |

The lists are the same `Shared.BSScrollingList` instances carrying `EntriesA` and
`iSelectedIndex` that the inventory menu publishes to, written the same way and through the
same code: rows, then `InvalidateListData`, then the selection.

**The barter half is its own contract.** `BarterMenu` defines five properties on its own
menu instance, read straight back off the movie after bring-up (`fBuyMult = 1.0`,
`fSellMult = 1.0`, `iPlayerGold = 0.0`, `iVendorGold = 0.0`, `iConfirmAmount = 0.0`), plus
`SetBarterMultipliers(afBuyMult, afSellMult)`. Publishing sets the two multipliers from
`BarterPricing.basePriceFactor` and writes the two purses. That the movie uses the
multipliers to scale a row's `value` into a displayed price is **inferred from the names
and from `SetBarterMultipliers`'s shape, not measured** — the engine's own prices come from
`BarterPricing` and never from the movie, so nothing depends on that reading being right.

`BottomBar.SetBarterInfo(aiPlayerGold, aiVendorGold, aiGoldDelta, astrVendorName)` is what
moves the player info card onto its `Barter` frame. `VendorGoldValue` is placed by that
frame and does not exist before it, which is why the container-mode movie has no vendor
field at all — the acceptance test asserts both halves of that. The gold delta is 0: it is
what a pending transaction would move, and nothing is ever pending here because the
quantity slider and the confirm step are not driven.

Engine calls registered per mode come from each movie's own constant pool. `CloseMenu` and
`ItemSelect` are in both; `ItemTransfer`, `TakeAllItems` and `EquipItem` are in
`containermenu.swf` only; `ShowRawDealWarning` and `GetRawDealWarningString` are in
`bartermenu.swf` only, and the latter answers the empty string because OpenSky has no
raw-deal rule.

## Verification

Sidebar path **World > Container Menu** (`Destination-containerMenu`), two sections:
`PanelSection-containerMerchant` and `PanelSection-containerMenu`. Controls:
`ContainerMerchantSelectControl`, `ContainerMerchantCrosshairControl`,
`ContainerMenuOpenControl`, `ContainerMenuCloseControl`, `ContainerMenuUpControl`,
`ContainerMenuDownControl`, `ContainerMenuSwitchSideControl`,
`ContainerMenuTransferControl`, `ContainerMenuTakeAllControl`,
`ContainerMenuBarterControl`, `ContainerMenuMovieControl`. Readouts:
`ContainerMenuStatsLabel`, `ContainerMerchantStatsLabel`. Every button routes the same
`MenuInputEvent` the keyboard produces, so the panel cannot diverge from live input.

Covering tests:

- `BarterPricingTests` — the price curve against the source's tabulated values, the Speech
  clamps, rounding, the trade caps, per-unit stack pricing, and GMST resolution including
  both fallbacks. Synthetic GMST fixtures built in code.
- `BarterSessionTests` — buy and sell conservation including gold, all four refusals, the
  zero-gold merchant, free items, and the journal entries a transaction leaves.
- `ContainerMenuModelTests` — sides, labels, per-side pricing, affordability and the
  selection restore.
- `ContainerMenuPanelTests` — accessibility ids, button enablement, the merchant popup, the
  readouts and the override/reset contract.
- `ContainerMenuAcceptanceRealDataTests` — the env-gated gate below.

The acceptance run drives each real movie at 1280x720 through bring-up, publication of a
real two-sided inventory, a navigation step and one transaction from each side:

| Measure | `containermenu.swf` | `bartermenu.swf` |
|---|---|---|
| Display nodes | 375 | 361 |
| Faults | 0 | 0 |
| Unimplemented opcodes | 0 | 0 |
| Unhandled bridge calls | 0 of 44 | 0 of 50 |
| Vendor gold field | absent | 840, matching the engine |
| Transactions | took, stored | bought for 78, sold for 40 |

Both runs assert that the totals of every item and of gold across the merchant and the
player are unchanged by the pair of transactions.

Reproduce without the test host with
`make run-cli ARGS="swf container-menu --mode barter --side player --down 2 --transfer 1"`.
Frames go to gitignored `logs/`; a rendered frame embeds the user's own assets and is never
committed.

## Limits / next

- **Single-unit transactions.** The vanilla `QuantitySlider` constructs but is never
  driven, and neither is the `ShowConfirmMessage` step, so every transfer and every trade
  moves one item. Recorded as the v1 limitation.
- **The merchant is a nominated container.** Faction-linked merchant chests, services,
  stock respawn and investment are M18+.
- **Speech, perks and Fortify Barter are fixed.** See
  [the formula](#the-price-formula); the modifier seam is where they will land.
- **Stolen goods and fences** have no rules here, which is why `GetRawDealWarningString`
  answers empty.
- **Category changes are engine-driven**, as they are for the inventory menu and for the
  same measured reason.
