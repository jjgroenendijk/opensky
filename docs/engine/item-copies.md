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
| Trapped soul | Soul trap | Recharging and enchanting |
| Enchantment charge | A hit with an enchanted weapon | [Item enchantments](/engine/item-enchantments.md) |
| Made enchantment | The enchanting table | Item enchantments |

The game keeps these in an extra data list on each copy. OpenSky keeps them per owner in one
component, apart from the counts: per item, a list of the copies that differ from the record.
Every copy past that list is plain. A reader takes only as many copies as the owner holds, so
a take or a drop needs no change to the list.

## Order

The list is kept best first: higher temper, then a made enchantment, then a bigger soul. Charge
does not count, and copies that tie keep their order. So a hit that spends charge does not move
the equipped role to another copy of the same weapon. The order decides two things:

- An equip wears the best copy, because the equipped set names a base item, not a copy.
- A move takes the plainest copies first, so the owner keeps the best one.

## Moves

Every move carries the copies it moves: a take, a drop into the world and the pick-up again, a
container, a gift, a trade, and a confiscation. A dropped Legendary sword is still Legendary
when picked up again, and a filled soul gem left in a chest is still filled.

The save keeps the levels in `TMPR` and the whole copy in `ICPY`
([save chunks](/formats/opensky-save-actor-chunks.md)).
