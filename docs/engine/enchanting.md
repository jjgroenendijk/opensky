---
type: Subsystem
title: Enchanting
description: How disenchanting teaches a base enchantment, how a new enchantment is scaled by
  skill, soul, and perks, how a weapon gets its charge, where a made enchantment is kept, and
  where OpenSky differs from the game.
tags: [engine, magic, enchanting, soul-gems, inventory]
---

# Enchanting

At an arcane enchanter the player does two things. Disenchanting destroys an enchanted item and
teaches its base enchantment. Enchanting puts known base enchantments on a plain weapon or piece of
apparel and spends a filled soul gem. A made enchantment then acts like any other
[item enchantment](/engine/item-enchantments.md).

## Sources

- UESP "Skyrim:Enchanting" (<https://en.uesp.net/wiki/Skyrim:Enchanting>), for the menu rules and
  the perks.
- UESP "Skyrim:Enchanting Effects" (<https://en.uesp.net/wiki/Skyrim:Enchanting_Effects>), for
  every formula below.
- UESP "Skyrim:Leveling" (<https://en.uesp.net/wiki/Skyrim:Leveling>), for the skill experience.
- The install's perk records, read with `openskycli record`, for the entry points.

## Disenchanting

The item must be carried and enchanted. A staff, and an item with the `MagicDisallowEnchanting`
keyword, cannot be disenchanted. The player learns the last link of the enchantment's base chain
([enchantment records](/formats/enchantments.md)): `EnchWeaponFireDamage02` teaches its base, not
itself. "The magnitude is irrelevant for purposes of disenchanting", and "only one item per effect
may ever be disenchanted", so a known base is refused and the item stays.

## Which base fits which item

A weapon takes a fire-and-forget base with contact delivery. Apparel takes a constant-effect base.
A staff cannot be enchanted, and an item that already has an enchantment, from its record or from
a made one, cannot take another. A base's worn restriction list (`ENIT`) must name one of the
item's keywords: this is what keeps Fortify Archery off boots. The list is read through the app,
which owns the form lists and the keyword index.

The item may take one base. `Mod # Applied Enchantments Allowed` (80) changes that: the Extra
Effect perk is a set-value entry of 2.

## Strength

UESP gives, for apparel, "rounded down":

```text
net magnitude = base magnitude * soul multiplier * skill multiplier * (1 + Enchanter perk)
                * (1 + specific perk modifier)
skill multiplier = 1 + (skill/100) * (skill/100 - 0.14) / 3.4
```

The soul multiplier is 1 for grand, 2/3 greater, 1/3 common, 1/6 lesser, and 1/12 petty. Every
perk term comes through `Mod Enchantment Power` (77), with the base bound to the enchantment tab
and the item to the item tab. In the install the Enchanter ranks are multiply-value entries of
1.2 to 2.0, each gated on not having the next rank. Fire Enchanter multiplies by 1.25 when the
enchantment tab has `MagicDamageFire`; an enchantment's `HasKeyword` reads the keywords of its
effects. So one product of perk factors covers the formula's perk terms.

The result is a power per base. A base's magnitude is multiplied by it where the `MGEF` has Power
Affects Magnitude, and its duration where it has Power Affects Duration. Both round down. UESP's
note that for Paralyze "only the duration is affected" is this flag rule. The install confirms the
flags: `EnchFortifyHealthConstantSelf` has `DATA` flags `0x00200A02`, which includes bit 21.

The skill is the Enchanting value as it is now. UESP: without the Unofficial Patch, Fortify
Enchanting "erroneously modifies Enchanting instead of Enchanting Power Modifier", so a potion
raises the skill term. OpenSky follows the unpatched game.

## Weapon charge

For a weapon "the maximum magnitude ... is generally not affected by the soul used". The soul
sets the charge instead: 250 petty up to 3000 grand ([soul trap](/engine/soul-trap.md)). One use
costs:

```text
charges per use = 3 * (base enchantment cost)^1.1 * (1 - sqrt(skill/200))
```

The costs of two bases add up. The skill term is capped below 200, where a use would cost nothing.
"If the soul is so small that the Number of Uses cannot reach 1", the power drops until one use
costs the whole soul: a use at power share `s` costs `s^1.1` of the full cost, so
`s = (soul / full cost)^(1/1.1)`. The game also has a slider to choose a lower magnitude. OpenSky
always uses the highest magnitude the soul allows.

## Experience

UESP "Skyrim:Leveling" gives the base experience, which Enchanting's skill use multiplier then
scales:

| Action | Base experience |
| --- | --- |
| Enchant an item | 1 |
| Disenchant | 1 per 400 gold of enchantment value |
| Recharge a weapon | 0.05 petty, 0.1 lesser, 0.2 common, 0.4 greater, 0.6 grand |

The enchantment value is the item's game value minus its record value: what the
[barter](/engine/barter.md) price adds for the enchantment.

## Where a made enchantment lives

No plugin holds a made enchantment, so the player's enchanting component does: the known bases and
every made enchantment, with its bases, a power per base, its charge, and its cost per use. A made
enchantment takes a FormID in mod index `0xFF` from `0xFF600000` up, below the brewed potions. The
enchanted [item copy](/engine/item-copies.md) names it. Its effects are rebuilt from the base
records whenever they are needed, so they stay right if a base record changes in a mod update.

The equipped role goes to an item's best copy, and a made enchantment ranks above a plain copy of
the same temper. So an enchanted copy is the one an equip wears. The save keeps the component in
the `ENCK` chunk ([save chunks](/formats/opensky-save-actor-chunks.md)).

## Where OpenSky differs

- A made enchantment combines bases of one plugin only, because one item profile reads all its
  effect links from one plugin. The panel says so when two plugins are mixed.
- The magnitude slider is not modelled: a weapon always gets the highest magnitude.
- An item is not renamed. The made enchantment's name is what the readouts show.
- The panel acts as if the player stood at an arcane enchanter.

## Controls

World > Inventory & Equipment > Enchanting: disenchant a carried item; enchant a plain item with
one or two known bases and a filled soul gem. The readout lists the known bases, how many bases an
item may take, and a preview of the power and charge before the gem is spent.
