---
type: Subsystem
title: Item enchantments
description: How a weapon enchantment fires on a hit and spends charge, how a worn enchantment
  grants constant effects, where charge is stored, why the worn restriction gates nothing, which
  actor values fortify effects move in the damage formulas, and what a save keeps.
tags: [engine, magic, enchantments, combat, inventory]
---

# Item enchantments

A weapon's enchantment fires on whatever it hits and spends charge. A worn item's enchantment grants
its effects while it is worn. A fortify effect from either one moves a damage number. The records are
on the [enchantment records](/formats/enchantments.md) page.

## Three shapes

The Creation Kit wiki states the authoring rules (<https://ck.uesp.net/wiki/Enchantment>): "Armor
Enchantments must use the 'Constant Effect' casting type" and "can only have 'Self' as their
delivery type". Weapons "can only have 'Contact'". Staves "can only use 'Aimed' or 'Target
Location'". Counted across the active load order:

| Reached from | Shape | Count |
| --- | --- | --- |
| `ARMO` `EITM` | Enchantment, constant effect, self | 2,885 |
| `WEAP` `EITM` | Enchantment, fire and forget, touch | 2,939 |
| `WEAP` `EITM` | Staff enchantment, aimed, target actor, or target location | 86 |

So the casting type chooses the behavior, not the record type: constant effect is worn, a weapon's
is contact, and a staff is neither. Every enchanted item in the load order falls into one of the
three, so an unexpected shape shows up as a wrong count, not a skipped item.

A staff is classified and counted, but not cast. Its trigger is a staff attack, not a landed hit, and
that belongs to the animation graph. Firing a staff's spell on contact is not what a staff does.

## Charge

Two numbers, both decoded, and no invented formula:

- Full charge is the weapon's own `EAMT`. `ARMO` has no such field, which fits a worn enchantment
  spending nothing.
- One use costs the enchantment's cost: the written `ENIT` value under the manual cost flag, and the
  auto-calculated total otherwise ([spell records](/formats/magic-records.md)).

So the number of uses is `floor(EAMT / cost)`. UESP's Generic Magic Weapons page prints a
"Charge/Cost = Uses" column for every generated magic weapon, as "base values, equivalent to the
values for a player with 0 in all skills" (<https://en.uesp.net/wiki/Skyrim:Generic_Magic_Weapons>).
Five rows checked against the install agree on all three numbers:

| Weapon | Charge | Cost | Uses |
| --- | --- | --- | --- |
| Dwarven Warhammer of Absorption | 1000 | 18 | 55 |
| Ebony Battleaxe of the Vampire | 3000 | 109 | 27 |
| Iron Battleaxe of Dismay | 500 | 7 | 71 |
| Imperial Bow of Cowardice | 300 | 11 | 27 |
| Elven Battleaxe of Banishing | 2000 | 138 | 14 |

A weapon with less than one whole use cannot fire, and the rest stays unused. Vanilla's enchanting
menu refuses a soul gem too small for "at least one charge"
(<https://en.uesp.net/wiki/Skyrim:Enchanting>), so part of a use is not a use. An enchantment with
zero cost is unmetered: it fires forever and writes no charge, so it does not mark its owner changed
on every swing.

The charge is spent before the effects apply, and once. A hit that cannot pay applies nothing. A hit
that can pay has paid, even if every entry is an archetype OpenSky does not run. The meter moves on
the swing, not on the effect, and a weapon with an unsupported enchantment cannot fire forever.

The cost is not scaled by skill. UESP says uses go up with "a relevant magic skill" and that skill 100
gives "about 1.7 times the uses documented here". Its formula for a player-made enchantment uses the
Enchanting skill instead. The two disagree about which skill counts, and 1.7 has no formula. So
OpenSky charges the base cost, the number the tables print.

An empty weapon stays empty. Recharging with soul gems is not implemented, and neither is enchanting
an item.

## Where charge is stored

Charge is part of the owner's enchanted item component ([runtime state](/engine/runtime-state.md)),
per item, with the effects each worn item applied.

Charge belongs to one item, but OpenSky has no identity per item instance yet. An item stack is keyed
by base form ID, so charge is too. So one owner holding two of the same enchanted weapon shares one
charge between them. Every access goes through a charge lookup by item, so only those signatures
change when a stack key includes more than the base.

## A landed hit

A contact enchantment applies through the same code as a landed spell
([spell delivery](/engine/spell-delivery.md)): each hostile entry is scaled by the target's
resistances and handed to the effect runtime. Only the charge is added.

So resistances apply to weapon enchantments. `ENIT` has no "ignore resistance" flag like `SPIT`
does. Its two documented bits are manual cost and extend duration on recast. So there is no way to
skip the step, and none is invented.

A swing and an arrow take the same path. The weapon's enchantment is fixed when the swing or shot
starts, so an arrow in the air applies the enchantment of the bow that fired it, not of whatever is
equipped when it lands.

## A worn item

A constant effect is a third effect mode. It holds its magnitude in the temporary slot like a
modifier, and nothing takes it back by itself. 618 of the 620 effect entries behind vanilla
constant-effect enchantments have an `EFIT` duration of zero, so reading zero as "apply once" would
be wrong here. A constant effect never expires.

Applying and removing is a reconcile, not an equip hook. The engine equips from several places: the
inventory menu, the Items panel, and a load. Hooking each one would be one missed call away from an
effect that never comes off. The reconcile takes who is wearing what and makes the stored constant
effects match. Running it twice changes nothing, and every equip path runs it afterwards.

Removal is exact, because the effects each item applied are recorded per item. A helmet and a
necklace can carry the same `ENCH`, as vanilla robes and circlets do, so removing by source record
would take off the other item's effects too.

Worn effects are not scaled by resistance. Resistance is for a hostile magnitude arriving from
outside.

An NPC wearing enchanted armor from its outfit gets nothing until something equips. The reconcile
runs on equip, unequip, and load, not on cell build. Walking every actor's equipment as cells stream
in is work that was not measured, and buffing an actor nobody is fighting shows nothing. The player
starts with nothing worn.

## The worn restriction

`ENIT`'s worn restriction is a form list of keywords. The Creation Kit describes it as an authoring
rule: "When the player tries to enchant a Weapon or piece of Armor with this Enchantment, only items
that have one of the keywords in this list may be enchanted with it."

It can be asked, but it is not checked when a worn item applies its effects, because checking it
would break vanilla items. Of the 2,727 enchanted `ARMO` records whose enchantment names a
restriction list, 70 have no keyword from their own list. Among them are the Gauldur Amulet and its
three fragments, a Dragon Priest mask, and Cicero's hat.

## Fortify effects in damage

UESP: "Many Fortify Skill enchantments actually affect the action directly instead of increasing your
skill" (<https://en.uesp.net/wiki/Skyrim:Enchanting_Effects>). The records say which value each one
moves. Every one is a Peak Value Modifier with Recover set:

| `MGEF` | Actor value | Index |
| --- | --- | --- |
| `EnchFortifyOneHandedConstantSelf` | One-Handed Modifier | 96 |
| `EnchFortifyTwoHandedConstantSelf` | Two-Handed Modifier | 97 |
| `EnchFortifyArcheryConstantSelf` | Marksman Modifier | 98 |
| `EnchFortifyBlockConstantSelf` | Block Modifier | 99 |
| `AlchFortifyOneHanded` | One-Handed Power Modifier | 135 |
| `AlchFortifyTwoHanded` | Two-Handed Power Modifier | 136 |
| `AlchFortifyMarksman` | Marksman Power Modifier | 137 |
| `AlchFortifyBlock` | Block Power Modifier | 138 |

So each combat action reads two values, the enchantment one and the potion one, and adds them. They
are not the same value: a worn item moves the first, and a potion the second. Reading one would drop
half the sources. The indices are looked up by vanilla name.

The magnitudes are percentage points, as the effects' own descriptions say: "One-handed attacks do
&lt;mag&gt;% more damage" (<https://en.uesp.net/wiki/Skyrim:Fortify_One-handed>), "Bows do
&lt;mag&gt;% more damage" (<https://en.uesp.net/wiki/Skyrim:Fortify_Marksman>), and "Block
&lt;mag&gt;% more damage with your shield" (<https://en.uesp.net/wiki/Skyrim:Fortify_Block>). The
multiplier is `1 + points / 100`, with points added first: the actor value is one sum, and UESP's
example (four 40% items give +160%) adds. Where each one lands is on the
[melee damage](/engine/melee-damage.md) and [projectiles](/engine/projectiles.md) pages.

## Saving

Charge and worn effects go in the `ECHG` chunk ([save
chunks](/formats/opensky-save-actor-chunks.md)). Charge is not in `INVN`: inventory entries are
counts, and charge is a float per item that changes on a hit, not on a transfer. The worn effect
list is the other half of the same fact, which `AEFF` effects each worn item owns. Splitting them
would let a load restore effects that nothing could take off.

## Where it shows

Charge is a fact about an equipped item, so it shows where equipped item details already show: World
> HUD & Interaction > Items, World > Inventory & Equipment > Equipment inspection, and the "Enchanted
equipment" block of World > Inventory Menu > Menu. One formatter makes all three lines (name, worn,
on-hit, or staff, and `remaining/capacity charge, N use(s) left`), so they cannot disagree.

A resolved enchantment depends only on two records, which nothing changes at runtime. So each item's
answer, including "no enchantment", is cached until the item store is replaced. The frame hooks ask
every frame for every equipped weapon and the bow. World > Inventory & Equipment > Equipment shows the
cache size and how many asks it served.
