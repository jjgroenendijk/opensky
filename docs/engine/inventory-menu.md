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

Categories group items by record type, in the vanilla tab order: Favorites, All, Weapons (`WEAP`
and `AMMO`), Apparel, Potions, Scrolls (`SCRL`), Food, Ingredients, Books, Keys (`KEYM`), and Misc.
Favorites takes the rows the player marked, of any type. Food takes the `ALCH` records with the food
flag, and Potions takes the rest, poisons included. Misc also holds soul gems (`SLGM`) and alchemy
apparatus (`APPA`). This is OpenSky's own grouping of the [item records](/formats/item-records.md),
not Bethesda's category numbers. The order is the one the game shows; it is not yet confirmed
against `InventoryDefines` in the movie. An item of unknown type shows under Misc, so All is not the
only way to find it. The menu opens on All, as the game does.

Each tab takes its name from a string setting: `sFavorites`, `sAllItems`, `sWeapons`, `sApparel`,
`sPotions`, `sScrolls`, `sFood`, `sIngredients`, `sBooks`, `sKeys`, and `sMisc`. Without a plugin
that sets one, the tab keeps OpenSky's English name.

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
- Eating an ingredient also teaches its first effect, and using a poison puts it on the drawn weapon
  ([alchemy](/engine/alchemy.md)). Any other row says so and changes nothing.
- R drops the row. A stack of more than five opens the quantity prompt first; a smaller one drops
  one copy. The limit is `QUANTITY_MENU_COUNT_LIMIT` in the movie's `InventoryDefines`.
- Space marks the row as a favourite, or unmarks it. The game uses F; OpenSky's menu bindings have
  no F, so the jump key stands in.

Every change reads the inventory again and writes it to the movie, so weight and gold stay current.

`ItemSelect` and `DropItem` are registered as host functions, because they appear in the movie's
bytecode. No measured run has called either, so they are not confirmed. Only `CloseMenu` is.

## Quantity

The quantity prompt asks how many of a stack to drop. It starts at the whole stack: the movie's
`ItemCard.ShowQuantityMenu` sets the slider's maximum and value to the stack count. Left and right
change the count by 1. Down and up change it by 10, which is OpenSky's own step. The count stays
between 1 and the stack. Accept or R drops that many, and cancel drops none.

## Favourites and hotkeys

A favourite is saved per player in the `FAVS` chunk
([actor chunks](/formats/opensky-save-actor-chunks.md#favs-favourites)). A favourite can be bound
to one of the hotkeys 1 to 8. Binding a key takes it from the item that held it, and unmarking a
favourite frees its key. In play, the number keys 1 to 8 are the input actions `Hotkey1` to
`Hotkey8` ([control map](/formats/controlmap.md)). A hotkey equips its item, or unequips it when
it is equipped. A potion, food, or ingredient is used, and a poison goes on the weapon. A key with
no item, or an item no longer carried, shows a notice and does nothing.

## Item card

The item card describes the selected row: its name and kind, value and weight, base damage or
armour rating, its effects, and whether it is a favourite or stolen. An ingredient's unknown effect
shows as `?`. The rating is the `ARMO` `DNAM` value divided by 100, before skill and perks.

The movie shows the same card. On a change of row, the menu calls `RequestItemCardInfo` through
`GameDelegate`. The engine answers through the `UpdateItemCardInfo` callback the menu registers,
with one object that becomes `ItemCard_mc.itemInfo`. These fields and numbers were read from the
installed `itemcard.swf` and its `InventoryDefines`:

| Field | Meaning |
| --- | --- |
| `type` | the card page: `ICT_ARMOR` 1, `ICT_WEAPON` 2, `ICT_MISC` 3, `ICT_BOOK` 4, `ICT_FOOD` 5, `ICT_POTION` 6, `ICT_INGREDIENT` 8, `ICT_KEY` 9, `ICT_SOUL_GEMS` 12 |
| `name`, `value`, `weight` | the header line |
| `damage`, `armor` | the weapon and armour numbers |
| `effects` | the effect text of a potion, food, weapon, or armour piece |
| `itemEffect0` to `itemEffect3`, `numItemEffects` | an ingredient's known effects; the movie shows `$UNKNOWN` for an index below `numItemEffects` that has no name |

OpenSky sends the card after each change it writes to the lists. A scroll uses the potion page,
which lists effects; the game's page for a scroll is not confirmed. The card's charge meter,
warmth, skill text, and book description are not filled.

## Item preview

The selected row's model turns beside the list. The model path is the record's `MODL`, or the male
world model for armour. It is drawn unlit with its diffuse texture, in front of the world, through
the menu scene that the [crafting menu](/engine/crafting.md#crafting-menu) uses. It
draws into a thin slice of depth near the camera, so the world cannot cover it. The model turns at
0.6 radians a second; the game's rate is not measured. A model with a `BSInvMarker` is first turned
by the marker's angles, and its fit size is multiplied by the marker's zoom
([NIF extra data](/formats/nif-extra-data.md#inventory-marker)). A model that fails to load logs its
reason and draws nothing.

## Gift menu

`Actor.ShowGiftMenu` opens `Interface\giftmenu.swf`. The movie uses the same list clips as
the inventory movie. With `abGivingGift` true the list holds the player's items, and each
pick moves one to the actor; with false it holds the actor's items. The other arguments follow
the [CK wiki](https://ck.uesp.net/wiki/ShowGiftMenu_-_Actor):

| Argument | Default | What OpenSky does |
| --- | --- | --- |
| `apFilterList` | `None` | Shows only an item that is in the list, or that has a keyword in the list |
| `abShowStolenItems` | `false` | Hides stolen copies unless it is true |
| `abUseFavorPoints` | `true` | Ignored. No source says how many favour points an item is worth |

The game's native is latent: it returns when the menu closes, with the favour points spent or
gained. OpenSky's native returns at once, with 0.

## Not done yet

- Category focus through the movie. It needs a live `InputDelegate`.
- The quantity slider and the 3D item in the movie itself. The engine holds the data;
  `ShowQuantityMenu` is not called, and `UpdateItem3D` and `EndItem3D` are answered with no action.

The container and barter menus reuse this row list and list code, one pane per side
([barter](/engine/barter.md)).
