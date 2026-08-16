---
type: Subsystem
title: Inventory menu
description: The player inventory menu - its engine-side row list and categories, the
  cross-movie character import that vanilla inventorymenu.swf needs before it has a list
  at all, the EntriesA data contract, and the navigation and equip/drop actions behind it.
tags: [engine, ui, menu, swf, inventory, scaleform]
timestamp: 2026-08-01T00:00:00Z
---

# Inventory menu

Milestone 12.2.2. The second menu OpenSky opens and the second implementer of
[menu mode](/engine/menu-mode.md)'s `MenuInputConsumer`. It lists what the player carries,
filters that list by category, and equips, unequips or drops the selected row — optionally
presenting itself through the vanilla `Interface\inventorymenu.swf` movie.

This is the milestone that owns the phase-4 inventory data contract the
[AS2 scope decision](/decisions/swf-as2-scope.md) deferred: `_CategoriesList`, `EntriesA`
and `iSelectedIndex`, filled from real inventory data.

Like the [system menu](/engine/system-menu.md), the subsystem is split so it works with no
install, no renderer and no movie. Only the presentation layer needs any of those.

## Contents

- [The row list](#the-row-list)
- [Cross-movie character import](#cross-movie-character-import)
- [The vanilla data contract](#the-vanilla-data-contract)
- [Navigation](#navigation)
- [Actions](#actions)
- [Verification](#verification)
- [Limits / next](#limits--next)

| Layer | File | Target |
|---|---|---|
| Row list and categories | `opensky/Engine/UI/InventoryMenuModel.swift` and `InventoryMenuModelBuild.swift` | app + CLI |
| Vanilla movie contract | `opensky/Engine/UI/InventoryMenuMovieBridge*.swift` | app + CLI |
| Panel seam | `opensky/Engine/InventoryMenuControlProviding.swift` | app + CLI |
| Renderer + AppKit wiring | `opensky/App/GameViewControllerInventoryMenu.swift` | app |
| Verification surface | `opensky/App/InventoryMenuPanelViewController.swift` and `opensky/App/Shell/Sections/InventoryMenuSection.swift` | app |

## The row list

`InventoryMenuModel` is a `nonisolated struct` built from a `ReferenceInventoryState` and an
`ItemDefinitionStore` — the two things [runtime state](/engine/runtime-state.md) already
owns — so it needs neither a store nor a renderer to exist. One row carries the item's
FormID, display name, count, unit weight, unit value, equipped flag and record family.

Three rules are worth stating because each is a decision rather than a consequence:

- **Gold is a readout, not a row.** `InventoryRuntime` models money as an ordinary `MISC`
  stack, so leaving it in the rows would show the player a "Gold001" line. It is filtered
  out of the rows and reported separately, while still counting toward carried weight —
  excluding it from the rows is a display choice, not an accounting one.
- **A form no loaded plugin describes still gets a row**, named by editor ID or FormID. It
  is something the player is genuinely carrying, and hiding it would lose the item.
- **Rows sort by display name, then FormID.** Two items sharing a name still order
  deterministically, which is what makes a published list comparable in a test.

Categories group `ItemDefinition.Family` — All, Weapons (WEAP and AMMO), Armor, Potions,
Ingredients, Books, Misc. That grouping is over OpenSky's own decode of the record types
[item records](/formats/records.md) reads, deliberately **not** a reproduction of Bethesda's
internal category numbering; a family OpenSky does not decode yet cannot appear. An item
whose family is unknown filters as Misc so the only way to reach it is not the All tab.

## Cross-movie character import

`inventorymenu.swf` cannot show a list until the SWF layer resolves imports across movies,
and that was the largest single piece of this milestone.

The movie places three characters it never defines. Measured with
`openskycli swf action-run --movie inventorymenu`:

```text
unresolved character 87 as "ItemCard_mc"
unresolved character 89 as "InventoryLists_mc"
unresolved character 90 as "BottomBar_mc"
imports from Inventory components/ItemCard.swf: 87 ITEM CARD BASE
imports from Inventory components/InventoryLists.swf: 89 InventoryLists
imports from Inventory components/BottomBar.swf: 90 BottomBar
```

Before the merge only fonts resolved imports, by name substitution, so those three
placements instantiated nothing: the menu came up as **11 display nodes with no list at
all**. `SWFMovieImportMerger` (see [SWF container](/formats/swf.md)) now merges each source
movie's characters, linkage names and `DoInitAction` blocks into the importer under a
uniform id offset. Afterwards the same movie brings up **373 nodes, 0 faults and 0
unimplemented opcodes**, with 16 registered classes instead of 10 — `InventoryLists`,
`ItemsList`, `CategoryList`, `BottomBar`, `ITEM CARD BASE` and `QuantitySlider` among them.

The measured merge for this movie is 3 source movies and 675 characters, 3 placeholders
bound, 0 unresolved, 8 imports skipped as font-only.

## The vanilla data contract

Measured paths, read back off the user's own installed movie. All three list clips come
from the imported subtree, so none of them exists without the merge above.

| Thing | Path |
|---|---|
| Menu (`InventoryMenuObj`) | `/Menu_mc` |
| Category list | `/Menu_mc/InventoryLists_mc/CategoriesListHolder/List_mc` |
| Item list | `/Menu_mc/InventoryLists_mc/ItemsListHolder/List_mc` |
| Gold field | `/Menu_mc/BottomBar_mc/PlayerInfoCard_mc/PlayerGoldValue` |
| Carry weight field | `/Menu_mc/BottomBar_mc/PlayerInfoCard_mc/CarryWeightValue` |

Both lists are `Shared.BSScrollingList` instances carrying `EntriesA` and `iSelectedIndex`,
which is exactly the contract the scope decision named. Publishing writes each list's
`EntriesA` with one plain object per row (`text`, `index`, `count`, `weight`, `value`,
`equipped`, `enabled`), then rebuilds, then sets the selection.

**The order matters and was measured, not assumed.** `InvalidateListData` — a `GameDelegate`
callback the movie registers for itself — rebuilds a list from its new data and resets
`iSelectedIndex` to its own nothing-selected sentinel of `-1` as it goes. A selection
written before the rebuild is silently discarded, so `publish` writes rows, invalidates, and
only then selects. Calling `InvalidateListData` on a display path instead of through the
delegate finds nothing and lands in the unhandled-invoke count; it is invoked by name.

The two totals are `TextField` instances on the player info card, not properties on the
bottom bar, so they are filled with the GFx `SetText` extension rather than assigned.

## Navigation

Up and down go through the movie's own CLIK focus path, and the movie's resulting
`iSelectedIndex` is what the engine adopts — the movie owns the row selection. The engine
performs the step the absent `InputDelegate` would, pointing `focusTarget` at the item list;
without that the movie consumes every arrow key and moves nothing.

**Category changes are engine-driven and republished**, which is a deliberate deviation.
Focusing the category list and sending up or down was measured and moves nothing: the movie
routes left and right through `InventoryLists_mc`'s own `strHideItemsCode` / `strShowItemsCode`
panel states rather than through the focus path, and with no live `InputDelegate` nothing
drives that transition. So left and right change category in `InventoryMenuModel`, and the
re-filtered rows are published to the movie, which re-renders both lists. The movie's
category list selection follows.

## Actions

**Consume** eats or drinks the selected row (issue #469): one unit leaves the inventory and
the item's effect list is applied to the player through the same
`GameViewController.consumeMagicItem` the Magic Effects panel button runs, so the two
surfaces cannot diverge. A row that is neither an `ALCH` nor an `INGR` reports that and
changes nothing. See [magic and active effects](/engine/magic.md).

Activating a row equips it, or unequips it when it is already equipped — the vanilla
toggle, so the player does not need to know a row's state before pressing anything. Equip,
unequip and drop call the same `ItemControlProviding` seam World > HUD & Interaction > Items
already uses (`equipItem`, `unequipItem`, `dropPlayerItem`), rather than reimplementing any
of them, so the menu and the panel cannot diverge on what equipping means. Every mutation
re-reads the inventory and republishes, so carry weight and gold stay live.

Driving the movie through bring-up, publication and navigation produced 46 outbound calls
and **none of them was an equip or a drop**. `ItemSelect` and `DropItem` are registered as
host functions on the strength of appearing in the movie's own bytecode, but no measured run
has invoked either, so they are recorded here as unconfirmed. Only `CloseMenu` is confirmed.

## Verification

Sidebar path **World > Inventory Menu > Menu** (`Destination-inventoryMenu`,
`PanelSection-inventoryMenu`). Controls: `InventoryMenuOpenControl`,
`InventoryMenuCloseControl`, `InventoryMenuUpControl`, `InventoryMenuDownControl`,
`InventoryMenuPreviousCategoryControl`, `InventoryMenuNextCategoryControl`,
`InventoryMenuEquipControl`, `InventoryMenuDropControl`, `InventoryMenuConsumeControl`,
`InventoryMenuMovieControl`.
Readout: `InventoryMenuStatsLabel`. Every button routes the same `MenuInputEvent` the
keyboard produces, so the panel cannot diverge from live input.

Covering tests:

- `InventoryMenuModelTests` — naming, sorting, per-row and total arithmetic, the gold
  split, category filtering, and the navigation clamps. Synthetic fixtures only.
- `InventoryMenuPanelTests` — accessibility ids, button enablement, the readout, and the
  override/reset contract.
- `SWFMovieImportMergeTests` — the import merge, against synthetic movies.
- `InventoryMenuAcceptanceRealDataTests` — the env-gated gate below.

The acceptance run drives the real movie at 1280x720 through bring-up, publication of a
real inventory, a category change and two row moves:

| Measure | Result |
|---|---|
| Display nodes | 373 |
| Faults | 0 |
| Unimplemented opcodes | 0 |
| Unhandled bridge calls | 0 of 46 |
| Distinct missing names | 53 (467 hits) |
| Bring-up changed pixels | 142,741 |
| Published changed pixels | 15,280 |

The 53 remaining missing names are CLIK cosmetics, headed by `_listeners` (53),
`height` and `width` (43 each), `getLineMetrics` (42), `invalidationIntervalID` (38),
`apply` (30) and `CLIK_loadCallback` (15). None is a data API.

Reproduce without the test host with
`make run-cli ARGS="swf inventory-menu --ticks 20 --down 3 --right 2"`. Frames go to
gitignored `logs/`; a rendered frame embeds the user's own assets and is never committed.

## Limits / next

- **The rotating 3D item preview is deferred.** `UpdateItem3D` and `EndItem3D` are answered
  as no-ops so the deferral is a named decision rather than an unhandled call.
- **Category focus is not driven through the movie.** See
  [Navigation](#navigation); the panel-state path would need a live `InputDelegate`.
- **The item card is built but not filled.** `ItemCard_mc` and its 222 frames come up, and
  `UpdateItemCardInfo` and `RequestItemCardInfo` exist on both sides, but no per-item card
  data is published.
- **Favorites, hotkeys and quantity selection** are out of scope; `QuantitySlider`
  constructs but is never driven.
- **Container and barter menus** reuse this CLIK groundwork, this bridge's list helpers
  and this row list, one pane each side; see
  [container and barter menus](/engine/barter.md).
- Categories are OpenSky's own family grouping, not the vanilla `InventoryDefines` tab
  order. Reading those constants off the movie and matching the vanilla strip is open.
