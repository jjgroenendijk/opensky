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

- item and container records: [item records](../formats/item-records.md);
- the inventory component: [runtime state](runtime-state.md);
- taking and dropping world items: [interaction](interaction.md);
- the menus: [inventory menu](inventory-menu.md) and [barter](barter.md).

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

A stack is keyed by the base FormID and the stolen flag, so stolen and honest copies of one item
are two stacks. The menu shows them as one row. A copy can also differ by its temper level, its
trapped soul, its enchantment charge, or an enchantment made at a table. Those live in a separate
list per item ([item copies](item-copies.md)); copies not in the list are plain.

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

`XOWN` and `XRNK` are decoded on each reference. For the crosshair target, OpenSky works out
whether taking it would be theft for the player now. This uses the reference's owner, the cell's
owner, and the player's faction ranks. It also shows the bounty if someone sees the take. See
[crime and bounty](crime.md).

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

## What an NPC wears

One routine decides what an NPC wears. It takes off what the NPC wears, except items a script
locked on, then puts on the items of its current outfit. It adds an outfit item the NPC no longer
holds. Then two picks follow:

- Armour, for a teammate only: for each body slot, low bit first, the held armour with the
  highest armour rating for that actor, its temper, skill, and perks included. Clothing scores 0.
  The score starts below any rating, and only a strictly higher one wins. On a tie the item held
  in the larger count wins, then the first one found. A later slot's pick can take off an earlier
  one it overlaps. Enchantment and value do not count.
- A weapon, for every NPC: the score is the weapon's damage for that actor, times its speed, times
  1.0 for melee or 0.2 for a bow or crossbow, times the combat style's melee or ranged weight. A
  weapon only the player may use, or one the race cannot use, is skipped. The score starts at 0,
  and only a strictly higher one wins; on a tie the larger count wins. Of two two-handed kinds the
  higher one stays. One weapon is worn, and a bow or crossbow also takes the first matching
  ammunition found. A dead or dying NPC, or one whose package puts weapons away or sleeps in a
  bed, skips this step.

The routine runs when the NPC's 3D is built fresh with nothing worn, such as after a cell change or
a load. It runs when armour or a weapon that is not bound moves between the player and a teammate,
either way. It also runs on a reset or respawn, when a script changes the outfit, and when a worn
item is removed. It has no timer, and the start of combat does not run it. So an NPC that is not a
teammate never wears armour it is given, and a dismissed follower goes back to its outfit at its
next run. This comes from a clean-room read of `SkyrimSE.exe` on 2026-11-24.

OpenSky runs the routine after a trade with a follower, and builds every NPC's starting set from it:
its outfit and its best carried weapon ([carried items](actor-resolution.md#carried-items)).
The armour rating is the record's own, without temper, skill, or perks. The weapon's damage is the
record's base damage. A tie on either pick keeps the first item found, whatever the counts.

## Budgets

The loop adds no budget of its own. The cell build and fly budgets check a cell whose actor wears
a runtime equipped set. With a menu open, every simulation clock moves by zero, so a paused frame
does no animation, audio, or script work.

## Hand occupancy

Which hands a weapon fills does not come from a bit field on the item. It comes from the `WEAP`
`ETYP` link, resolved through the `EQUP` records of the same plugin
([shout records](../formats/shouts-equip-slots.md)):

| Slot | Hands |
| --- | --- |
| `EitherHand` | right, or left when equipped into the left hand |
| `BothHands` | both |
| `Shield` | left |
| A slot that names no hand, like `Voice` or `Potion` | none |

A shield is the one armour piece with an `ETYP`: it names `Shield`, so it fills the left hand.
That makes a shield and a two-handed weapon conflict, and equipping one unequips the other, as in
the game. Other vanilla armour has no `ETYP` and fills no hand.

Ammunition (`AMMO`) fills neither a hand nor a body slot. It has a slot of its own, so equipping
one kind of arrow unequips the other, and it never conflicts with a weapon or armour.

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
- After an item is equipped, the spellbook empties every hand a worn item holds.

A spell's `ETYP` needs one difference a weapon's never did. `BothHands` and `EitherHand` name the
same two parents. They differ only in the "use all parents" byte of `DATA`, because the player
chooses the hand for a spell. The slot table keeps the two apart for spells, and still gives the
one fixed answer for weapons. Casting is on the [magic](magic.md) page.

## Carry weight

The player is over-encumbered when the carried weight is above the `CarryWeight` actor value ([UESP
Carry Weight](https://en.uesp.net/wiki/Skyrim:Carry_Weight)). Worn armour counts at its perk weight
([perk entry points](perk-entry-points.md#armour-weight)). An over-encumbered player can
only walk: run and sprint fall back to walking. The HUD shows `sOverEncumbered` once, when the state
starts. Fast travel is refused too ([world map](world-map.md)). The check runs every frame,
so dropping an item or raising the actor value lifts the state at once.

## Not done yet

- A dropped object with a simulated Havok body falls and settles
  ([dynamic rigid bodies](dynamic-bodies.md)). One without a dynamic body stays where
  it was placed.
