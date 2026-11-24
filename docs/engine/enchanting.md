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
- A clean-room read of `SkyrimSE.exe` on 2026-11-24, for the check on a typed name.

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
skill multiplier = 1 + (fEnchantingSkillFactor - 1) * (skill/100) * max(0.01, (skill - 14) / 85)
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

The costs of two bases add up before the power of 1.1. The skill term is capped below 200,
where a use would cost nothing. UESP says the charge per use is "calculated at the moment of the
usage", but the game stores the cost with the skill of the moment of making, as the next section
says. OpenSky follows the game.

## The magnitude slider in the game

The slider shows only for a weapon enchantment whose highest magnitude is above 1. Apparel never
gets one. It runs from 1 to the highest magnitude. Its step grows with that maximum:

| Highest magnitude | Step |
| --- | --- |
| 30 or less | 1 |
| Above 30 | 2 |
| Above 60 | 5 |
| Above 120 | 10 |

The highest magnitude is the strength above, rounded down. A base whose effect has Power Affects
Duration and not Power Affects Magnitude scales its duration instead. The chosen value is kept
within 1 and the maximum. When the maximum changes, the chosen value jumps to the new maximum.

The soul's share is its value over a grand soul's 3000. For apparel the magnitude is the maximum
times that share, at least 1. For a weapon the soul does not change the slider; it only gives the
charge. Before a gem is chosen, the menu previews with the largest soul among the listed gems. The
UESP rule that a tiny soul lowers a weapon's maximum was not found in the game program.

Charge and uses:

```text
total charge = soul value, through Mod Soul Gem Enchanting, at least 0
per use      = 3 x (sum of base cost x chosen / maximum)^1.1 x (1 - sqrt(skill / 200))
uses shown   = floor(total charge / per use)
```

The base cost is the `ENIT` cost under the manual cost flag, else the sum of the effect costs, then
Mod Spell Cost. The cost follows the chosen share of the maximum, so a perk that raises the maximum
does not raise the cost at the maximum. The new enchantment stores the per-use cost, fraction
dropped, with the manual cost flag set. The new item gets the total charge, fraction dropped.

The made item's gold value:

```text
apparel: item value + enchantment cost, rounded half up
weapon:  item value + 0.12 x charge + 8 x enchantment cost, fraction dropped
```

Example: a 25 gold sword, Fire Damage with base magnitude 10, Enchanting 15, no perks, a grand
soul. The base cost is `0.9 x 10^1.1 = 11.33`. The maximum is 10, so the slider runs 1 to 10 in
steps of 1.

- At 10: one use costs `3 x 11.33^1.1 x 0.7261 = 31.46`, so 95 uses. The sword is worth
  `25 + 0.12 x 3000 + 8 x 31 = 633`.
- At 5: one use costs `3 x 5.665^1.1 x 0.7261 = 14.68`, so 204 uses.

## Experience

UESP "Skyrim:Leveling" gives the base experience, which Enchanting's skill use multiplier then
scales:

| Action | Base experience |
| --- | --- |
| Enchant an item | 1 |
| Disenchant | `fDisenchantSkillUse` (0.0025) per gold of enchantment value: 1 per 400 gold |
| Recharge a weapon | The soul's charge times `fSkillUsageRechargeMult` (0.0002): 0.05 petty, 0.6 grand |

The enchantment value is the item's game value minus its record value: what the
[barter](/engine/barter.md) price adds for the enchantment.

## Where a made enchantment lives

No plugin holds a made enchantment, so the player's enchanting component does: the known bases and
every made enchantment, with its bases, a power per base, its charge, and its cost per use at
Enchanting 0. A made
enchantment takes a FormID in mod index `0xFF` from `0xFF600000` up, below the brewed potions. The
enchanted [item copy](/engine/item-copies.md) names it. Its effects are rebuilt from the base
records whenever they are needed, so they stay right if a base record changes in a mod update.
Each base keeps its effects in the plugin that holds it, so one made enchantment can combine
bases from different plugins.

The equipped role goes to an item's best copy, and a made enchantment ranks above a plain copy of
the same temper. So an enchanted copy is the one an equip wears. The save keeps the component in
the `ENCK` chunk ([save chunks](/formats/opensky-save-actor-chunks.md)).

## Enchanting menu

Using an arcane enchanter (a `FURN` whose `WBDT` bench type is enchanting) opens the
[crafting menu](/engine/crafting.md#crafting-menu) with the header
`<sEnchanting>: <sEnchantMenuDescription>`. It has four tabs in this order:

| Tab | Setting | Rows |
| --- | --- | --- |
| Disenchant | `sDisenchant` | Carried enchanted items, known enchantments included; no staff |
| Item | `sItem` | Carried plain weapons and apparel |
| Enchantment | `sEnchantment` | The known base enchantments |
| Soul Gem | `sSoulGem` | Carried filled soul gems, with the soul's size |

The accept key on a Disenchant row asks `sConfirmDisenchant` with Yes and No. Yes destroys
the item. A new enchantment shows `sEnchantmentsLearned` in a message box with one Ok button
(`sOk`); `%s` is the enchantment's name. A known one shows `sEnchantmentKnown` on the HUD and
keeps the item. On the other tabs the accept key chooses the row, or takes it out again. The
second key makes the item. Without an item, an enchantment, and a gem it shows
`sEnchantMustChooseItems`. A base that does not fit the item shows `sEnchantArmorIncompatible`,
and an empty gem `sEnchantInsufficientCharge`. Otherwise it asks `sEnchantItem` and makes the
item on Yes.

Choosing a weapon base with a weapon chosen opens the movie's magnitude slider when the
slider applies: OpenSky calls `ShowSlider(maximum, 1, value, step)` on the menu. The movie calls
`CalculateCharge([value])` as the slider moves, and `SliderClose([value, accepted])` when it
closes. A cancel keeps the value from before. The readout shows the magnitude and the uses.

With a full choice, the third key opens the [name field](/engine/text-entry.md) titled by the
`sEnterItemName` button text. The name takes at most 32 characters, the PC limit on
[UESP](https://en.uesp.net/wiki/Skyrim:Enchanting). Without a name, the made enchantment is named
after its bases, joined by ` + `. A typed name goes on the made [copy](/engine/item-copies.md),
and the enchantment keeps the names of its bases.

The game checks a typed name only against a list of allowed characters. There is no word
filter on PC. The list is the rest of the `validNameChars` line in the interface font
configuration ([SWF text](/formats/swf-text.md#fontconfigtxt)). Every character of the name must
be in the list, matched exactly and with case. An empty name fails. A name that fails is dropped
with no message: the field closes and the item keeps the name it had, the made one or an earlier
typed one. A cancel keeps it too. The game uses the same check for the character name in the race
menu. With the Japanese or Chinese language, the game also takes characters in fixed code-point
ranges; OpenSky does not, because those ranges were not read.
