---
type: Subsystem
title: Inventory state
description: How an owner's inventory is stored as a full override, how baselines are derived again
  from records, the accounting rules for add, remove, transfer, weight, and gold, and how an equip
  resolves slot conflicts.
tags: [engine, inventory, equipment, runtime-state, save-state]
---

# Inventory state

Inventory is a component in the [world state store](runtime-state.md). How the player uses it
(taking, dropping, containers, menus) is on the [inventory and equipment](inventory-equipment.md)
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

The initializer enforces two rules, both for determinism: stacks are sorted by form ID, then honest
before stolen, with one entry per (item, stolen) pair and every count above zero. The equipped set
is sorted with no duplicates. So two stores that reached the same inventory in different orders give
equal snapshots and identical save bytes. How copies of one item can differ is on the
[inventory and equipment](inventory-equipment.md#stacking) page.

Inventory travels in its own `INVN` chunk, not inside `RDLT`, so an older build skips it by length
instead of refusing the file ([save chunks](../formats/opensky-save-world-chunks.md)).

## Baselines

A baseline is derived from plugin data on every call and never cached, so a reset restores whatever
the records say now. The caller says what kind of owner it has, because a `ReferenceKey` cannot: the
store knows nothing about record types.

| Owner | Baseline |
| --- | --- |
| Container | The `CONT` `CNTO` list, with leveled entries expanded. Nothing equipped |
| Actor | Its carried `CNTO` items and its default outfit from the resolved template chain, one of each piece. The outfit is the baseline equipped set |
| Player | The `Player` record, read as an actor |
| Generated | Empty. A runtime object such as a dropped pile or a summon |

The actor case uses the template resolver ([actor records](../formats/actors.md)), which already
follows `TPLT` links and the `ACBS` "Use Inventory" flag. The outfit is worn, not only carried,
because a default outfit is by definition what the actor has on. Carrying it unworn would start every
NPC naked.

Leveled entries roll at the owner's encounter level ([leveled lists](leveled-lists.md)). The
roll is seeded by the owner, so a baseline read twice at one level gives the same items. A cycle is
caught by a visited set and a depth limit of eight.

An actor also carries its own `CNTO` items, through the same "Use Inventory" flag, unworn.

One simplification, narrowing rather than wrong:

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
[inventory and equipment](inventory-equipment.md) page.

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
([actor resolution](actor-resolution.md)). The player uses the same API.

Removing the last copy of a worn item also unequips it. An owner never wears what it does not hold.

## The left hand

A one-handed weapon can go into the left hand. In the game the player does this with the left
attack button in an item menu: the install's `controlmap.txt` binds `LeftEquip` to the same button
as `Left Attack/Block`. UESP calls a weapon in each hand dual wielding
(<https://en.uesp.net/wiki/Skyrim:Block>).

The equipped set holds every worn item once. The inventory also keeps the left-hand item, and
whether a second copy of it is in the right hand. So two iron swords from one stack can be worn
together. Example: the player holds two iron swords and equips one, then puts one in the left hand.
The equipped set is the iron sword, and the left hand is the iron sword, paired.

- A weapon equipped into the left hand takes off a shield, a two-handed weapon, and the old
  left-hand weapon. The right-hand weapon stays.
- A weapon equipped into the right hand keeps the left-hand weapon. A shield or a two-handed
  weapon takes it off.
- The left-hand item equipped again into the right hand makes a pair, when the owner holds two.
  With one copy, the weapon moves to the right hand. A one-copy right-hand weapon equipped into the
  left hand moves there too.
- A pair loses only the copy in the hand something else takes. Removing a copy of a pair keeps the
  last one in the right hand.
- Readying a spell in one hand takes the weapon out of that hand only.
- Only a weapon whose `ETYP` resolves to `EitherHand` goes to the left hand. Anything else asked
  for the left hand is equipped as usual.

An outfit can list two one-handed weapons, and nothing records a hand for them. The second one,
in form ID order, is the left-hand weapon. This rule decides only while no left-hand item is
stored.

## Script item natives

Papyrus scripts change inventories through `AddItem`, `RemoveItem`, `RemoveAllItems`,
`GetItemCount`, `EquipItem`, `UnequipItem`, and `SetOutfit`. The behaviour follows the Creation Kit
wiki pages for `ObjectReference Script` and `Actor Script`. The receiver can be the player, a placed
actor, or any other placed reference, which then holds items as a container.

A change to the player shows a HUD notice unless the call passes `abSilent` (`AddSpell` passes
`abVerbose = false` instead). The words come from `sAddItemtoInventory`,
`sRemoveItemfromInventory`, `sEquipItemOnPlayer`, `sUnequipItemOnPlayer`, and
`sAddItemtoSpellList`. The wiki pages do not give the full line. OpenSky writes the name, the count
in brackets when it is more than one, and then the word: "Iron Arrow (12) added". A change to an NPC
shows nothing, as the `AddSpell` page states for spells.

Scripts read equipment through `IsEquipped`, `GetEquippedWeapon`, and `GetEquippedShield`,
and take everything off with `UnequipAll`. `UnequipItemSlot(aiSlot)` takes off every worn item
that covers biped slot `aiSlot`, 30 to 61; a slot outside that range fails.
`Form.GetGoldValue` answers the item's `DATA` value.

- `GetEquippedWeapon(abLeftHand = false)` answers a weapon in the right hand, two-handed
  weapons included. With `abLeftHand` it answers a weapon that takes only the left hand.
- `GetEquippedShield` answers the worn armour in biped slot 39.
- `GetGoldValue` answers -1 for a form that is no item. This is OpenSky's choice; no source
  this project reached says what the game answers.
- `RemoveItem` takes at most what is held. A request for more is not an error.
- `RemoveItem` and `RemoveAllItems` move the items into the reference in their container argument,
  when the script names one. Otherwise the items are gone.
- `EquipItem` gives the actor one copy first when it holds none. This is the one place an item is
  equipped "from nowhere". The wiki page says the game does the same, and the opening relies on
  it: stage 10 of `MQ101` removes all the player's items, then equips the prisoner clothes.
- `RemoveAllItems` keeps [quest items](inventory-menu.md#quest-items) unless
  `abRemoveQuestItems` is true.
- `DropObject(akObject, aiCount = 1)` drops at most what the player carries, as one stack in front
  of the player, and returns the new reference. Only the player drops, because OpenSky places a
  drop only in front of the player's camera. A drop from another holder fails with that reason.

`SetOutfit` replaces an actor's outfit. The pieces of the actor's current outfit leave its
inventory, then one of each new piece is given and worn. A leveled entry rolls for the actor's base,
as a default outfit does. The equip-slot rules unequip anything else the new pieces cover.

The current outfit is the last one a script set, else the default outfit (`DOFT`). The game keeps
a set outfit too: a save stores it on the actor base as `CHANGE_NPC_DEFAULT_OUTFIT`
(<https://en.uesp.net/wiki/Skyrim_Mod:NPC_ChangeForm>). OpenSky keeps it in the actor's inventory
state, so the save stores it with the inventory. Example: a quest sets a prisoner's outfit to rags,
then to guard armour. The second call takes the rags off, not the prisoner's default clothes.

With `abSleepOutfit` set, the outfit is stored as the sleep outfit and nothing is worn. The game
does the same. The Creation Kit wiki says the Sleep Outfit field is "Not used"
(<https://ck.uesp.net/wiki/Inventory_Tab>), and that the package flag that wore it "was removed
from the final game" (<https://ck.uesp.net/wiki/Package_Flags>). A save still stores it
(`CHANGE_NPC_SLEEP_OUTFIT`).
