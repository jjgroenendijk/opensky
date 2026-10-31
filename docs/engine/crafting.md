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
opens a session with no recipes. An alchemy lab (bench type alchemy or alchemy experiment)
brews from ingredients instead ([alchemy](/engine/alchemy.md)). Enchanting uses its own system,
not `COBJ`.

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

The conditions decide whether the recipe is listed at all. The CK wiki calls them "Match
Conditions", the "pre-requisites for the recipe to appear in the crafting menu" ([Constructible
Object](https://ck.uesp.net/wiki/Constructible_Object)). So the crafting menu hides a recipe whose
conditions fail. Missing components only mark the row as not makeable.

## What a craft writes

A craft removes every component and adds the created object at its `NAM1` count (one when
absent). Both happen in one inventory write, so a failed step writes nothing. A recipe that is
not eligible is refused before anything changes.

A component the player holds both stolen and owned copies of is taken from the stolen copies
first. So the stolen mark leaves with the parts, and the made item is the player's own. The
game's order is not documented; this is a choice that keeps the player's own copies. The same
rule applies to tempering parts and alchemy ingredients.

After the write, the session reports one skill use for the station's `WBDT` skill. UESP
"Skyrim:Leveling" gives the amount as `count * (25 + 3 * value^0.65)`, where `value` is the
base value of one made item. The three numbers are the settings `fConstructibleSkillUseConst`,
`fConstructibleSkillUseMult`, and `fConstructibleSkilluseExp`. The `AVIF` skill-use
multiplier and offset then turn the amount into experience
([skill advancement](/engine/skill-advancement.md)). A bench with no skill reports nothing.

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
| effective skill | `(skill - 13.29) * (1 + perk) + 13.29`; `1 + perk` is the Mod Tempering Health value |
| damage or rating bonus | `(3.6 * level - 1.6) * factor`; factor 1 for body armor, else 0.5 |

Levels 1 to 6 are Fine, Superior, Exquisite, Flawless, Epic, and Legendary. Skill 15 reaches
Fine and skill 100 reaches Flawless. The names come from the string settings
`sHealthDataPrefixWeap1` to `6` for weapons and `sHealthDataPrefixArmo1` to `6` for armour;
without a string table the UESP names above stay. A level past the sixth reads as the sixth name
with the extra levels, such as `Legendary +1`.

Quality is stored per copy, apart from the item counts, in the owner's
[item copies](/engine/item-copies.md). The save keeps the levels in the `TMPR` chunk
([save chunks](/formats/opensky-save-actor-chunks.md)).

The player's weapon damage adds the bonus of the best held copy, because the equipped set
names a base item, not a copy. In the same way, the armour step of combat adds the bonus of the
best worn copy to its rating ([combat](/engine/combat.md)).

Quality belongs to the copy. Every move carries the levels of the copies it moves: a take, a
drop into the world and the pick-up again, a container, a gift, and a trade. The lowest copies
leave first, so the owner keeps the best one, which an equip wears. A merchant prices a tempered
copy at the UESP value multiplier `1 + level / 6`. A [cell reset](/engine/cell-reset.md) of a
container clears the quality of the copies it held, because its contents go back to the
plugin's.

Differences from the game:

- The skill use amount is `3.8 * sqrt(value gain) * sqrt(levels gained)`, times
  `fTemperingSkillUseMult`. The value gain is the base value times the rise in the UESP
  value multiplier (`1 + level / 6`). Players measured this formula (UESP "Skyrim
  talk:Smithing"). It is uncertain: the settings `fTemperingSkillUseItemValConst`,
  `...ItemValMult`, and `...ItemValExp` (25, 8, 0.6) do not fit it, and no source says how the
  game uses them, so OpenSky does not read them.
- The matching material perk, which doubles the skill above the offset, is not read.

## Refused crafts

A craft that fails shows a string setting on the HUD:

| case | setting |
| --- | --- |
| a forge recipe without its components | `sLackRequiredToCreate` |
| a temper whose `EPTemperingItemIsEnchanted` condition fails | `sLackRequiredPerkToImproveMagical` |
| a temper whose other condition fails, such as a material perk | `sLackRequiredPerksToImprove` |
| a temper without its components | `sLackRequiredToImprove` |
| a copy already at the best quality the skill reaches | `sLackRequiredSkillToImprove` |

A tempering bench lists every held item that has a recipe, even when its conditions fail, so the
player can see why it cannot be improved. A forge still hides a recipe whose conditions fail.
Which condition the game checks first is OpenSky's reading.

## Crafting menu

Using a station opens `Interface\craftingmenu.swf` over the session. The engine calls
`/Menu.Initialize` and `SetPlatform`, writes the station name into
`/Menu/MenuNameHolder/MenuName`, and sets `bCanCraft`. The lists are
`/Menu/InventoryLists/CategoriesListHolder/List_mc` and `.../ItemsListHolder/List_mc`, the
same list class as the [inventory menu](/engine/inventory-menu.md#list-data). OpenSky shows
two tabs: the recipes the player can make now, and all recipes.

The movie calls `CraftSelectedItem` or `CraftButtonPress` to make the selected recipe, and
`CloseMenu` to leave, which closes the session. At an alchemy lab the movie lists the carried
ingredients, with their known effects, on an Ingredients tab and a Chosen tab. Activate chooses or
drops an ingredient, a chosen one shows as equipped, and R brews. The game splits a forge's recipes
into tabs by material keyword, shows the item in 3D (`ShowItem3D`), and lets the player rename an
enchanted item and set its charge; OpenSky answers those calls and does nothing.

## Not modeled yet

- Perk entry points that change crafting, such as Arcane Blacksmith and the material perks.
- `GetVMQuestVariable`, which the evaluator does not know.
