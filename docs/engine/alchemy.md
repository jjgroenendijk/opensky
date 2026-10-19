---
type: Subsystem
title: Alchemy
description: How an alchemy lab brews a potion or poison from two or three ingredients, how
  the skill and the perks scale it, how the player learns ingredient effects, and how a poison
  goes on a weapon.
tags: [engine, alchemy, crafting, inventory, perks]
---

# Alchemy

An alchemy lab is a crafting station whose workbench data (`WBDT`) has the alchemy bench type.
It offers no `COBJ` recipes ([crafting](/engine/crafting.md)). Instead the player chooses two or
three carried ingredients, and the lab makes a potion or a poison from the effects they share.

Sources: UESP [Skyrim:Alchemy](https://en.uesp.net/wiki/Skyrim:Alchemy) and
[Skyrim:Alchemy Effects](https://en.uesp.net/wiki/Skyrim:Alchemy_Effects) for the formulas, and
the CK wiki [Perk Entry Point](https://ck.uesp.net/wiki/Perk_Entry_Point) and
[Ingredient Script](https://ck.uesp.net/wiki/Ingredient_Script) for the perks and natives. The
formulas come from community measurements, not from a spec.

## Shared effects

An `INGR` record lists four effects. An effect is shared when at least two chosen ingredients
list the same `MGEF`. Each ingredient can give its own magnitude and duration for that effect.
The brew uses the version whose cost at power 1 is highest.

A brew with no shared effect fails. The ingredients are still used up, as in the game, and the
player gets `fWortFailSkillUseMagnitude` as skill use. The notice is `sPotionCreationFailed`.

## Strength

The power factor is:

```text
power = fAlchemyIngredientInitMult * (1 + (fAlchemySkillFactor - 1) * skill / 100)
```

Skyrim.esm sets `fAlchemySkillFactor` to 1.5. `fAlchemyIngredientInitMult` is not in the
plugin, so its engine default 4 from UESP applies. Power scales the magnitude only when the
`MGEF` has "Power Affects Magnitude", and the duration only when it has "Power Affects
Duration". Both round to the nearest whole number.

Mod Alchemy Effectiveness (entry point 66) multiplies power for each effect. The Alchemist,
Physician, Benefactor, and Poisoner perks use it, and so does Fortify Alchemy, through the
`AlchemySkillBoosts` and `PerkSkillBoosts` perks. So OpenSky does not add Fortify Alchemy to the
skill a second time. While the entry point runs, the EPAlchemy conditions read the brew in
progress: `EPAlchemyGetMakingPoison` reads whether it is a poison, and
`EPAlchemyEffectHasKeyword` reads the keywords of the effect being scaled
([world conditions](/engine/condition-functions-world.md#spells)).

## Potion or poison

The costliest effect decides. If it has the Hostile flag, the brew is a poison; otherwise it is
a potion. Purify Alchemy Ingredients (entry point 73, the Purity perk) keeps only the effects
that match: good ones in a potion, bad ones in a poison.

## Value

The cost of one effect is:

```text
cost = floor(BaseCost * (magnitude * duration / 10) ^ 1.1)
```

A magnitude of 0 counts as 1, and a duration of 0 counts as 10 seconds. The value of the brew is
the sum of its effect costs. The skill use is the same sum at the skill alone, without perks.
UESP says the skill use is the value; whether the game counts the value before or after perks
is not confirmed.

## The made item

The name is `sCreatedPotionNamePrefix` or `sCreatedPoisonNamePrefix`, then the name of the
costliest effect, for example "Potion of Restore Health". Every made item weighs 0.5. No plugin
holds it, so it gets a FormID in mod index `0xFF` from `0xFF800000` up, and the save keeps it in
the `CPOT` chunk ([actor chunks](/formats/opensky-save-actor-chunks.md#cpot-created-potions)).
Two brews with the same effects make the same item, so they stack. A made item has no world
model in OpenSky, so dropping one leaves nothing visible.

Mod Potions Created (entry point 89) sets how many items one brew makes, with the made item
bound as the item.

## Learning effects

The player knows an effect of an ingredient once it is learnt. Brewing teaches every shared effect
of every chosen ingredient. A failed brew shares no effect, so it teaches nothing. Eating an
ingredient teaches its first effect. Mod Initial Ingredient Effects Learned (entry point 72, the
Experimenter perk) sets how many first effects eating teaches. The knowledge is saved in `INGK`.

The Papyrus natives `Ingredient.LearnEffect`, `LearnNextEffect`, `LearnAllEffects`, and
`IsHostile`, and `Potion.IsHostile`, read and write the same knowledge. `IsHostile` on an
ingredient reads its costliest effect, which is how a brew of it would decide. The wiki does not
say which effect the game reads.

## Poison on a weapon

Using a poison puts it on the weapon in the right hand, or the first held weapon. A new poison
replaces the old one. Mod Poison Dose Count (entry point 83, the Concentrated Poison perk) sets
how many hits it lasts, with the poison bound as the item. Each landed melee hit or arrow from
that weapon spends one dose and applies the poison's effects to the target. The state is saved in
`WPSN`.

## Where OpenSky differs

- The game has an alchemy menu. OpenSky has no lab movie yet; the sidebar drives the lab.
- Stolen copies of an ingredient are used up first, so the stolen mark leaves with them.

## Controls

World > Inventory & Equipment > Alchemy opens a lab from the list of lab bases, lists the
carried ingredients with their known effects, picks up to three, shows what they make, and
brews. It also eats an ingredient to learn from it, and puts a carried poison on the drawn
weapon. The readout shows the poison on each weapon and its doses.
