---
type: Subsystem
title: Inventory and equipment
description: The item loop from take to save, why items are only created by grants, how
  ownership is reported, how appearance skips are counted, and how hands are filled.
tags: [engine, inventory, equipment, app-ui]
---

# Inventory and equipment

This page covers how the item systems work together as one game loop: walk to an item, take it,
open a container, move items, equip, buy, sell, drop, save, and load. The parts are on their own
pages:

- item and container records: [item records](/formats/item-records.md);
- the inventory component: [runtime state](/engine/runtime-state.md);
- taking and dropping world items: [interaction](/engine/interaction.md);
- the menus: [inventory menu](/engine/inventory-menu.md) and [barter](/engine/barter.md).

## The loop

Each step is one runtime call.

| Step | What must hold |
| --- | --- |
| Grant | The only step that creates items, and it says so |
| Take | The item enters an inventory. The reference is deleted in its own cell |
| Transfer | Both sides change. The total across them does not |
| Equip | The equipped set is written to the actor's cell. A piece in a used slot replaces the old one |
| Buy | Gold moves one way and the item the other, in one write |
| Sell | The merchant pays less than it charged. Gold is still kept whole |
| Drop | One item leaves the player. One spawned reference appears |
| Save | The whole change set is written, with the key counter |
| Load | A new world state ends up in the same state |

Nothing is created or destroyed after the grant. A container's starting contents come from its
`CNTO` list, which can resolve a leveled list. So the totals are read from the data, not assumed.

A refusal writes nothing. A merchant with no gold still sells. A player who cannot pay keeps
their gold. Equipping an item the owner does not hold is a typed failure, and the equipped set
does not change.

## Stacking

Every item stacks by its base FormID. Two copies of one item are the same. Tempering,
enchanting, charge, or health would make copies differ. Those need a larger stack key first.

## Grants

A grant is a developer control. The real game has no such thing. The loop needs a known item in
a known inventory before it can move one, and searching the world for one cannot be repeated. A
grant is the plain "add to inventory" call, so it reaches the change log, the dirty counts, and
the save exactly like a taken item.

A grant is refused, with a message, for:

- a count of 0 or less;
- a form no loaded plugin describes. An unknown form has no weight, value, or name, so it would
  add a number the data never gave.

A grant goes to the player or to the open container. A merchant is a container too, so granting
into an open merchant chest adds to its stock.

## Ownership

`XOWN` and `XRNK` are decoded on each reference. The readout for the crosshair target says
whether taking it would be theft for the player now. This uses the reference's owner, the cell's
owner, and the player's faction ranks. It also shows the bounty if someone sees the take. See
[crime and bounty](/engine/crime.md).

There are four answers. None is left blank:

- no target;
- a target no one owns: taking it is not theft;
- a target with an owner the player may use: also not theft;
- a target the player may not use, with the faction rank if one is set and the bounty. An owner
  that comes from the cell says so, because the reference itself names none.

A null `XOWN` means no owner. It does not mean "owned by form 0".

## Appearance skips

An equipped piece can take a slot and draw nothing. Without a record of that, it would look the
same as an equip that did nothing. So every skip for every built actor is counted, whether the
actor draws or not, as `ACHR <id>: <reason> (<subject>)`. The cell load summary carries the list.

Only appearance skips are listed. The other skip kinds are about loading files, and the failure
counts already cover those. Mixing them would make a missing NIF look like an appearance choice.

The list is not part of the cell's exact count of drawn and failed items. An actor whose skin
torso is hidden by a cuirass draws correctly and still reports a skip. Counting that as a failure
would be wrong, because it is the outfit working.

The skips for one actor are found by filtering the loaded cells' lists by the prefix `ACHR <id>:`,
with the trailing space. A cell has few actors, and a rebuild rewrites the whole list. A separate
map per actor would be a second structure to keep in step, for no gain.

## Budgets

The loop adds no budget of its own. The cell build and fly budgets check a cell whose actor wears
a runtime equipped set. With a menu open, every simulation clock moves by zero, so a paused frame
does no animation, audio, or script work.

## Hand occupancy

Which hands a weapon fills does not come from a bit field on the item. It comes from the `WEAP`
`ETYP` link, resolved through the `EQUP` records of the same plugin
([shout records](/formats/shouts-equip-slots.md)):

| Slot | Hands |
| --- | --- |
| `EitherHand` | right |
| `BothHands` | both |
| `Shield` | left |
| A slot that names no hand, like `Voice` or `Potion` | none |

A weapon whose `ETYP` resolves to nothing takes the right hand and is counted as unresolved. So
a load order with many misses is visible, not quietly plausible. In vanilla, 5 weapons have no
`ETYP` at all, and every other one resolves.

## Spells in hands

A readied spell fills a hand too, but it does not go through the equipment runtime. Equipment
refuses anything the owner does not hold. That refusal guards against items from nowhere. A
spell is never held: it has no stack, no weight, and no item entry. Widening the refusal for
spells would drop the guard for every other caller.

The spellbook runtime owns readied spells in its own component. The two sides share only the
hands:

- Readying a spell unequips the weapon or shield in that hand.
- Equipping an item goes through the spellbook, which unequips a spell in the needed hand.

A spell's `ETYP` needs one difference a weapon's never did. `BothHands` and `EitherHand` name the
same two parents. They differ only in the "use all parents" byte of `DATA`, because the player
chooses the hand for a spell. The slot table keeps the two apart for spells, and still gives the
one fixed answer for weapons. Casting is on the [magic](/engine/magic.md) page.

## Not done yet

- Armor fills body slots only. `ARMO` also has an `ETYP`, which is not decoded. So a shield
  conflicts with a cuirass by body slot, but not yet with a two-handed weapon by hand.
- Carry weight is computed and shown, but nothing is slowed by it.
- A dropped object with a simulated Havok body falls and settles
  ([dynamic rigid bodies](/engine/dynamic-bodies.md)). One without a dynamic body stays where
  it was placed.

## Controls

World > Inventory & Equipment has three sections:

- Grants: a FormID, a count, and a target (player or open container).
- Ownership: the theft verdict for the crosshair target.
- Equipment inspection: the equipped set and appearance skips of the player or the nearest NPC.
  The player is the default.

The rest of the loop lives in one place each, so no control has two owners:

- take, search, take all, drop, equip, unequip: World > HUD & Interaction > Items;
- merchants, buying, and selling: World > Container Menu;
- save and load: World > Runtime State > Save.

A grant does not mark the panel as changed. A grant is a world change, and World > Runtime State
already resets those.
