---
type: Subsystem
title: Inventory menu
description: The player inventory menu - its row list and categories, the list data the vanilla
  inventorymenu.swf reads, why the call order matters, navigation, and the equip and drop
  actions.
tags: [engine, ui, menu, swf, inventory, scaleform]
---

# Inventory menu

The inventory menu lists what the player carries, filters it by category, and equips, unequips,
drops, or uses the selected row. It can show itself through the vanilla `Interface\inventorymenu.swf`
movie. It is a [menu mode](/engine/menu-mode.md) consumer. Like the
[system menu](/engine/system-menu.md), it works with no install, renderer, or movie. Only the movie
layer needs them.

This menu fills the inventory list data that the [ActionScript scope](/decisions/swf-as2-scope.md)
decision left for later: `_CategoriesList`, `EntriesA`, and `iSelectedIndex`.

## Row list

The row list is built from the player's inventory state and the item index (see
[runtime state](/engine/runtime-state.md)). A row has the item's FormID, name, count, weight, value,
equipped flag, and record type.

Three rules are choices, not results:

- Gold is a readout, not a row. The inventory stores money as a normal `MISC` stack, so as a row it
  would show "Gold001". It still counts toward carried weight. Hiding the row is a display choice,
  not an accounting one.
- An item no loaded plugin describes still gets a row, named by editor ID or FormID. The player
  really carries it, and hiding it would lose it.
- Rows sort by name, then FormID. So two items with the same name always have the same order.

Categories group items by record type: All, Weapons (`WEAP` and `AMMO`), Armor, Potions,
Ingredients, Books, and Misc. Misc also holds keys (`KEYM`), soul gems (`SLGM`), and alchemy
apparatus (`APPA`). This is OpenSky's own grouping of the [item records](/formats/item-records.md)
it decodes, not Bethesda's category numbers. An item of unknown type shows under Misc, so All is not
the only way to find it.

## Imported parts

`inventorymenu.swf` places `ItemCard_mc`, `InventoryLists_mc`, and `BottomBar_mc`, but defines none
of them. They come from three movies under `Inventory components/`. Without merging those movies in,
the menu has no list at all. See [SWF display list imports](/formats/swf-display-list.md#importassets-57-and-importassets2-71).

## List data

These paths were read from the installed movie. All three lists come from the imported parts.

| Part | Path |
| --- | --- |
| Menu (`InventoryMenuObj`) | `/Menu_mc` |
| Category list | `/Menu_mc/InventoryLists_mc/CategoriesListHolder/List_mc` |
| Item list | `/Menu_mc/InventoryLists_mc/ItemsListHolder/List_mc` |
| Gold | `/Menu_mc/BottomBar_mc/PlayerInfoCard_mc/PlayerGoldValue` |
| Carry weight | `/Menu_mc/BottomBar_mc/PlayerInfoCard_mc/CarryWeightValue` |

Both lists are `Shared.BSScrollingList` objects with `EntriesA` and `iSelectedIndex`. OpenSky writes
one plain object per row into `EntriesA`: `text`, `index`, `count`, `weight`, `value`, `equipped`,
and `enabled`.

The order of calls matters, and was measured. `InvalidateListData`, a `GameDelegate` callback the
movie registers for itself, rebuilds a list and resets `iSelectedIndex` to -1. A selection written
before it is lost. So OpenSky writes the rows, then calls `InvalidateListData` by name through the
delegate, then sets the selection. Calling it on a display path instead finds nothing.

Gold and carry weight are text fields on the player info card, not properties of the bottom bar.
They are set with the GFx `SetText` extension.

## Navigation

Up and down go through the movie's own CLIK focus path. The engine adopts the `iSelectedIndex` the
movie ends up with, so the movie owns the row selection. The engine does the one step the missing
`InputDelegate` would do: it points `focusTarget` at the item list. Without that, the movie takes
every arrow key and moves nothing.

Categories are changed by the engine, on purpose. Sending up or down to the focused category list
was tried and moves nothing. The movie changes categories through the `strHideItemsCode` and
`strShowItemsCode` states of `InventoryLists_mc`, and with no live `InputDelegate` nothing starts
that change. So left and right change the category in the engine, and the new rows are written to
the movie, which draws both lists again.

## Actions

- Activate equips a row, or unequips it if it is equipped. This is the vanilla toggle.
- Equip, unequip, and drop use the same calls as World > HUD & Interaction > Items. So the menu and
  the panel cannot differ on what equipping means.
- Use eats or drinks the selected row: one unit leaves the inventory, and its effects apply to the
  player, through the same call as the Magic Effects panel ([magic](/engine/magic.md)). A row that
  is not an `ALCH` or `INGR` says so and changes nothing.

Every change reads the inventory again and writes it to the movie, so weight and gold stay current.

`ItemSelect` and `DropItem` are registered as host functions, because they appear in the movie's
bytecode. No measured run has called either, so they are not confirmed. Only `CloseMenu` is.

## Controls

World > Inventory Menu > Menu has Open, Close, Up, Down, Previous and Next category, Equip, Drop,
Use, and a vanilla movie switch, over a readout. Every button sends the same menu event as the
keyboard.

`make run-cli ARGS="swf inventory-menu --ticks 20 --down 3 --right 2"` drives the real movie from
the command line. Frames go to `.logs/`, because a drawn frame contains the user's game art.

## Not done yet

- The turning 3D item preview. `UpdateItem3D` and `EndItem3D` are answered with no action, so the
  gap is a named choice, not an unhandled call.
- Category focus through the movie. It needs a live `InputDelegate`.
- The item card. `ItemCard_mc` loads, but no item data is sent to it.
- Favorites, hotkeys, and choosing a quantity. `QuantitySlider` loads but is never used.
- The vanilla category tab order from `InventoryDefines`.

The container and barter menus reuse this row list and list code, one pane per side
([barter](/engine/barter.md)).
