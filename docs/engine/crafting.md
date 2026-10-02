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

## Not modeled yet

- Tempering. A tempering recipe makes the item it improves, so crafting it would make a copy.
  A sharpening wheel or an armor table (bench types smithing weapon and smithing armor)
  therefore lists nothing. Item quality needs per-instance data.
- Perk entry points that change crafting, such as Arcane Blacksmith.
- `EPTemperingItemIsEnchanted` and `GetVMQuestVariable`, which the evaluator does not know.

## Controls

World > Inventory & Equipment > Crafting opens any station from a list of the item plugin's
benches, lists the recipes with their verdicts, and crafts the selected one. The Harvest
section beside it shows the crosshair plant and can force or reset a harvest
([interaction](/engine/interaction.md)).
