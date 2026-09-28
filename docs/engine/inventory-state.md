---
type: Subsystem
title: Inventory state
description: How an owner's inventory is stored as a full override, how baselines are derived again
  from records, the accounting rules for add, remove, transfer, weight, and gold, and how an equip
  resolves slot conflicts.
tags: [engine, inventory, equipment, runtime-state, save-state]
---

# Inventory state

Inventory is a component in the [world state store](/engine/runtime-state.md). How the player uses it
(taking, dropping, containers, menus) is on the [inventory and equipment](/engine/inventory-equipment.md)
page.

## A full override

The inventory component holds an owner's whole inventory once anything has touched it: stacks of
base item form ID and count, and for an actor, the equipped set. The first change copies the plugin
baseline into the component, and every later change edits that. An owner nothing has touched has no
component and derives from plugin data.

It is a full override, not a difference, because a difference has nowhere sensible to live. A `CONT`
whose `CNTO` list points at an `LVLI` has no stable "minus one iron sword": the list it would differ
from is itself a resolution. It does have a stable resolved list, and once the player opened the
chest, that list is the truth.

The initializer enforces two rules, both for determinism: stacks are sorted by form ID, with one
entry per item and every count above zero, and the equipped set is sorted with no duplicates. So two
stores that reached the same inventory in different orders give equal snapshots and identical save
bytes. Stacking is by base form ID alone ([inventory and equipment](/engine/inventory-equipment.md)).

Inventory travels in its own `INVN` chunk, not inside `RDLT`, so an older build skips it by length
instead of refusing the file ([save chunks](/formats/save-chunks.md)).

## Baselines

A baseline is derived from plugin data on every call and never cached, so a reset restores whatever
the records say now. The caller says what kind of owner it has, because a `ReferenceKey` cannot: the
store knows nothing about record types.

| Owner | Baseline |
| --- | --- |
| Container | The `CONT` `CNTO` list, with leveled entries expanded. Nothing equipped |
| Actor | The default outfit from the resolved template chain, one of each piece. The same items are the baseline equipped set |
| Player | Empty. No record describes the player here |
| Generated | Empty. A runtime object such as a dropped pile or a summon |

The actor case uses the template resolver ([actor records](/formats/actors.md)), which already
follows `TPLT` links and the `ACBS` "Use Inventory" flag. The outfit is worn, not only carried,
because a default outfit is by definition what the actor has on. Carrying it unworn would start every
NPC naked.

Four simplifications, each one narrowing rather than wrong:

- Leveled entries resolve the same way every time: the highest level entry, plus the "use all" flag.
  This is the rule the actor template chain uses for `LVLN`. Rolling against player level needs a
  player level. A cycle is caught by a visited set and a depth limit of eight.
- `chanceNone` is ignored. Ignoring it can only add an item the list might have skipped, and an empty
  container is the harder failure to notice.
- The actor baseline is its outfit, not any other loot it carries.
- A form that is neither a known item nor a leveled list is kept as a plain stack, not dropped. It
  really is in the container. It has no weight or value here, because no loaded index describes it.

## Accounting

The inventory runtime sits beside the store, not inside it. The store knows keys, components,
journals, and snapshots, and nothing about records. Inventory needs the item store for weights and
the baseline resolver for baselines.

Every change passes a holder: the key, the owner kind, and the cell the change belongs to, together.
Passing them apart is how a change ends up in the wrong cell.

- Add and remove write through the store, so every change reaches the journal, the dirty counts, and
  the save, like a script's `Disable()`.
- Transfer computes both new inventories before writing either. A transfer that cannot finish writes
  nothing, and the total across the two owners never changes. It journals two entries: source, then
  destination.
- Removing more than the owner holds is an error, not a clamp. A caller that meant "take everything"
  can ask how much there is. One that did not has a bug worth showing. A count of zero or less, and
  a stack that would pass `Int32`, are errors too.
- Carried weight and value add up each item's weight and value. An item no loaded index describes
  adds nothing. A guessed weight would put an invented number into an encumbrance check.
- Gold is an ordinary stack of an ordinary `MISC` record. The default is `Gold001`
  (`Skyrim.esm:0000000F`, value 1, weight 0), confirmed in the install. It is a setting, not a
  constant, because a total conversion need not use `Skyrim.esm`'s gold.

## Equipping

The equipment runtime sits over the inventory runtime, because equipping needs slot data the
inventory layer should not hold. What each item occupies, body slots and hands, is on the
[inventory and equipment](/engine/inventory-equipment.md) page.

An equip computes the whole new equipped set before writing anything. So a refused equip changes
nothing, and an accepted one is one journal entry, not one per removed piece. A new item unequips
everything that overlaps it in body slots or hands, so no two equipped items ever claim the same slot
or hand.

Two things are refused, not worked around:

- Equipping something the owner does not hold. Equipping an item from nowhere is how a duplication
  bug hides. Give the item first.
- Equipping something with no slots. A potion conflicts with nothing, so it would stay in the
  equipped set forever and no conflict would ever remove it.

Unequipping something not worn is not an error: the state the caller asked for already holds.

Equipping moves nothing between owners, so carried weight and value do not change: worn armor is
still carried. The write belongs to the owner's cell, so only that cell rebuilds, and the rebuilt
actor resolves its appearance from the equipped set instead of its default outfit
([actor appearance](/engine/actor-appearance.md)). The player uses the same API.
