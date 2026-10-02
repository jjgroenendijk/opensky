---
type: File Format
title: Recipes (COBJ)
description: Layout of Skyrim SE COBJ constructible objects, how OpenSky indexes them, and the
  recipe census of the vanilla masters.
tags: [format, plugin, records, crafting]
---

# Recipes

A `COBJ` constructible object is one crafting recipe. It lists the items it uses, the
conditions that must pass, the keyword of the station that offers it, and the item it makes.
A COBJ is not an item: nothing carries it. The stations are `FURN` records with workbench
data, on [world records](/formats/world-records.md).

Sources: UESP "Skyrim Mod:Mod File Format/COBJ"
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/COBJ>) and xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/9fb016884bec138ea6c7b872cec831537d464c3e/Core/wbDefinitionsTES5.pas)
(`wbRecord(COBJ, ...)` at line 8275, `wbCNTONoReach` at line 2233). All integers are
little-endian.

## Fields

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `COCT` | uint32 | number of `CNTO` fields; advisory only |
| `CNTO` | FormID + int32 | one component: an item, `FLST`, or `LVLI`, and a count |
| `CITC`, `CTDA`, `CIS1`, `CIS2` | | condition list, as on [conditions](/formats/conditions.md) |
| `CNAM` | FormID | created object |
| `BNAM` | FormID | workbench keyword, a `KYWD` |
| `NAM1` | uint16 | created count |

xEdit allows these created-object types: `ALCH`, `AMMO`, `ARMO`, `BOOK`, `INGR`, `KEYM`,
`LIGH`, `MISC`, `SCRL`, `SLGM`, `WEAP`. When `NAM1` is absent the game makes one item, so the
store reads a missing count as 1. A field that is too short is counted as malformed, and the
rest of the recipe still decodes.

## How OpenSky indexes recipes

The recipe store keeps the winning definition of each COBJ in load order. It answers two
questions from two indexes: which recipes a station offers (by workbench keyword), and which
recipes make an item (by created object). Each list is in load order. A plugin that overrides
a recipe moves it to its new keyword and drops it from the old one. Component targets stay as
resolved FormIDs; the crafting session expands a `FLST` through the form-list store.

## Confirmed on the real install

The five masters (`Skyrim.esm`, `Update.esm`, `Dawnguard.esm`, `HearthFires.esm`,
`Dragonborn.esm`) carry 1,387 COBJ records, and all of them decode with no unread field. Two
are overrides, so the store holds 1,385 recipes. `RecipeWeaponIronSword` makes `IronSword` at
`CraftingSmithingForge`.

Seven vanilla recipes have a null `CNAM`, for example `RecipeArmorSteelPlateShield` and
`TemperArmorGildedElvenBoots`. They make nothing. Every other created-object link resolves,
and every workbench keyword names a `KYWD`.

Recipes per workbench keyword, largest first:

| keyword | recipes |
| --- | --- |
| `CraftingSmithingArmorTable` | 319 |
| `CraftingSmithingForge` | 242 |
| `CraftingSmithingSharpeningWheel` | 204 |
| `BYOHBuildingCarpenter` | 200 |
| `BYOHBuildingDrafting` | 51 |
| `DLC2StaffEnchanter` | 43 |
| `CraftingCookpot` | 23 |
| `BYOHBuildingTrophyBase2` | 18 |
| `CraftingTanningRack` | 17 |
| `CraftingSmelter` | 16 |
| `BYOHCraftingOven` | 12 |
| `BYOHBuildingTrophyBase1` | 11 |
| `DLC1CraftingDawnguard` | 10 |
| `CraftingSmithingSkyforge` | 9 |
| `DLC1LD_CraftingForgeAetherium` | 3 |

Hearthfire also gives each house furnishing its own keyword: 205 `BYOHBuildingInteriorPart...`
keywords hold one or two recipes each. Two test keywords, `isGrainMill` and
`testPhilCraftingBreakItDowner`, hold one recipe each.

Component targets: 2,324 MISC, 145 INGR, 69 ALCH, 58 WEAP, 10 ARMO, 8 AMMO, and 2 SLGM. No
vanilla component is a `FLST` or an `LVLI`, so no shared leveled-list store is needed for
recipes.

Condition functions in COBJ conditions, with whether the OpenSky condition evaluator has
them:

| function | index | uses | evaluator |
| --- | --- | --- | --- |
| `GetItemCount` | 47 | 1,005 | no |
| `HasPerk` | 448 | 728 | yes |
| `EPTemperingItemIsEnchanted` | 659 | 523 | no |
| `GetGlobalValue` | 74 | 67 | yes |
| `HasSpell` | 264 | 43 | yes |
| `GetVMQuestVariable` | 629 | 38 | no |
| `GetStageDone` | 59 | 30 | yes |
| `GetQuestCompleted` | 543 | 8 | yes |
| `GetInCurrentLoc` | 359 | 3 | yes |
| `HasKeyword` | 560 | 1 | yes |

The function names come from the xEdit condition table in the same file.
