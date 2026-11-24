---
type: Subsystem
title: Item copies
description: How one copy of an item differs from its record - temper level, trapped soul,
  enchantment charge, and a made enchantment - and how a move carries it.
tags: [engine, inventory, crafting, enchanting, soul-gems]
---

# Item copies

An inventory counts items by base form ID. Some facts belong to one copy, not to the record:

| Fact | Set by | Read by |
| --- | --- | --- |
| Temper level | [Crafting](/engine/crafting.md) at a grindstone or workbench | Weapon damage, armour rating, price |
| Trapped soul | [Soul trap](/engine/soul-trap.md) | Recharging and enchanting |
| Enchantment charge | A hit with an enchanted weapon | [Item enchantments](/engine/item-enchantments.md) |
| Made enchantment | [Enchanting](/engine/enchanting.md) | Item enchantments |
| Custom name | The enchanter's name field | The inventory rows and the item card |
| Poison and doses | [Alchemy](/engine/alchemy.md#poison-on-a-weapon) | A landed weapon hit |
| Chosen mark | A menu row action | The order below |

The game keeps these in an extra data list on each copy. OpenSky keeps them per owner in one
component, apart from the counts: per item, a list of the copies that differ from the record.
Every copy past that list is plain. A reader takes only as many copies as the owner holds, so
a take or a drop needs no change to the list.

## Order

The list is kept best first: the chosen copy, then higher temper, then a made enchantment, then a
bigger soul. Charge, name, and poison do not count, and copies that tie keep their order. So a hit
that spends charge does not move the equipped role to another copy of the same weapon. The order
decides two things:

- An equip wears the best copy, because the equipped set names a base item, not a copy.
- A move takes the plainest copies first, so the owner keeps the best one.

## Moves

Every move carries the copies it moves: a take, a drop into the world and the pick-up again, a
container, a gift, a trade, and a confiscation. A dropped Legendary sword is still Legendary
when picked up again, and a filled soul gem left in a chest is still filled.

The save keeps the levels in `TMPR` and the whole copy in `ICPY`
([save chunks](/formats/opensky-save-actor-chunks.md)).

## Names and poisons in the game

The game keeps two more facts on each copy:

- **A custom name.** The name typed at the enchanter is checked by a word filter first; a name
  that fails is not used. An accepted name goes on the new copy, not on the base record. The
  inventory and favourites menus show one row per copy whose own facts differ, such as a name, an
  enchantment, a charge, a poison, or a temper level. That row shows the custom name, and the
  other rows show the base name. The name stays with the copy when it is dropped, worn, or sold.
- **A poison.** The poison and its doses left belong to the weapon copy it was put on, not to the
  base weapon. Taking the weapon off keeps the poison on that copy.

OpenSky keeps both on the copy. The inventory, its favourites tab, and the container and barter
lists show one row per kind of copy, best first, with the copy's name and value. The best copy's
row holds the equipped mark. An action on a row acts on that row's copy: OpenSky marks the copy
chosen, so an equip wears it, and a move takes that copy first. The mark leaves the copy when it
moves.
