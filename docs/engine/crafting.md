---
type: Subsystem
title: Crafting
description: How a crafting station opens a session, how a recipe gets its verdict, what a
  craft writes, and where OpenSky differs from the game.
tags: [engine, crafting, inventory, conditions]
---

# Crafting

A crafting station is a `FURN` base with workbench data (`WBDT`). Using it opens a crafting
session. The session lists the recipes the station offers, says for each one whether the
player can make it, and makes one on request. The session has no UI of its own, like a
container session. The record layouts are on [recipes](/formats/recipes.md) and
[world records](/formats/world-records.md).

## Which recipes a station offers

A recipe's `BNAM` names a keyword. A station offers every recipe whose keyword is in the
station's `KWDA`. The bench type does not decide this. A station whose keywords name no recipe,
such as an alchemy lab, opens a session with no recipes. Alchemy and enchanting use other
systems, not `COBJ`.

The use key raises a crafting activation event beside the plain interaction event. The
inventory coordinator opens the session on it. Opening a new session closes the old one.

## Item identities

The recipe store covers the whole load order, and its links are `(plugin, object)` pairs. The
inventory keys items by the raw FormIDs of the plugin the item index was built from, which is
`Skyrim.esm` today. The session converts each link into that plugin's FormID through its
master list. A link into a plugin the item plugin does not list cannot be held, so the recipe
reads `item not loaded`.

## The verdict

A verdict has three parts, checked every time the session is read:

| part | meaning |
| --- | --- |
| conditions | the name of the first function whose OR group is false |
| components | each item the player holds too few of, with held and needed counts |
| unresolved | a component or the created object outside the item index |

Repeated components of one item add up before the check. The conditions run with the player
as subject. `GetItemCount` reads the player's inventory, and the rest read the live condition
context of the session. A function the evaluator does not know makes its group false, so the
verdict names it, for example `function 4725` for `GetVMQuestVariable`.

## What a craft writes

A craft removes every component and adds the created object at its `NAM1` count (one when
absent). Both happen in one inventory write, so a failed step writes nothing. A recipe that is
not eligible is refused before anything changes.

After the write, the session reports one skill use for the station's `WBDT` skill. The amount
is the base value of the made stack. UESP "Skyrim:Leveling" lists Smithing experience as based
on the value of the item made. The `AVIF` skill-use multiplier and offset then turn the amount
into experience ([skill advancement](/engine/skill-advancement.md)). A bench with no skill
reports nothing.

## Tempering

A sharpening wheel or an armor table (bench types smithing weapon and smithing armor) improves
an item instead of making one. Its recipes look like crafting recipes, but the created object
is the item to improve. Checked on the install: `TemperArmorIronCuirass` creates the iron
cuirass from one iron ingot, with the conditions `EPTemperingItemIsEnchanted != 1` OR
`HasPerk == 1` (Arcane Blacksmith).

The station lists one row per recipe whose item the player holds. A temper uses up the parts,
keeps the item count, and raises one held copy to the best quality the skill reaches. It
picks the lowest copy below that quality. `EPTemperingItemIsEnchanted` reads whether that
item's record has an enchantment.

The formulas come from UESP "Skyrim:Smithing":

| what | formula |
| --- | --- |
| best quality level | `floor((effective skill + 38) * 3 / 103)` |
| effective skill | `(skill - 13.29) * (1 + perk) + 13.29` |
| damage or rating bonus | `(3.6 * level - 1.6) * factor`; factor 1 for body armor, else 0.5 |

Levels 1 to 6 are Fine, Superior, Exquisite, Flawless, Epic, and Legendary. Skill 15 reaches
Fine and skill 100 reaches Flawless.

Quality is stored per copy, apart from the item counts: per owner and item, one level for
each improved copy. Copies past that list are plain. A reader uses only as many levels as
the owner holds copies, so a take or a drop needs no change to the list. The save keeps the
levels in the `TMPR` chunk ([save chunks](/formats/opensky-save-actor-chunks.md)).

The player's weapon damage adds the bonus of the best held copy, because the equipped set
names a base item, not a copy. Armor rating is shown in the station row; no damage step
reads armor rating yet.

Differences from the game:

- A copy that leaves the player loses its quality. The game keeps it on the item.
- The skill use amount is the base value times the rise in the UESP value multiplier
  (`1 + level / 6`), not the UESP experience formula.
- The matching material perk, which doubles the skill above the offset, is not read.

## Not modeled yet

- Perk entry points that change crafting, such as Arcane Blacksmith and the material perks.
- `GetVMQuestVariable`, which the evaluator does not know.

## Controls

World > Inventory & Equipment > Crafting opens any station from a list of the item plugin's
benches, lists the recipes with their verdicts, and crafts the selected one. At a tempering
bench each row names the quality of every held copy and the damage or rating change, and
Craft improves one copy. The Harvest
section beside it shows the crosshair plant and can force or reset a harvest
([interaction](/engine/interaction.md)).
