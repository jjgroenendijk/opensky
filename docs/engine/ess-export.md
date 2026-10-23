---
type: Engine
title: Skyrim Save Export
description: How OpenSky writes a session as a Skyrim SE .ess save, what it writes, what it writes empty, and what is not confirmed yet.
tags: [save, ess, export]
---

# Skyrim save export

OpenSky can write the running session as a Skyrim Special Edition save. The export is the
reverse of the [import](/engine/ess-import.md): each part the import reads, the export
writes, and a test checks that a written save imports back to the same state. The file
layout is on the format pages: [ESS](/formats/ess.md),
[ESS change forms](/formats/ess-change-forms.md), and
[ESS Papyrus](/formats/ess-papyrus.md).

The export is pure. The same session and the same plugins give the same bytes. Only the
header's file time and save number come from the clock and the folder.

## Where a user meets it

- The in-game Save page ends with an `Export to Skyrim` row.
- It writes into the Skyrim saves folder setting (see
  [the saves folder](/engine/ess-import.md#the-saves-folder)). Each export is a new file,
  `OpenSky Export N.ess`, with the first free number. The write fails rather than replace
  a file, so a save the game wrote is never overwritten.

## What is written

| Session state | In the save |
| --- | --- |
| Player identity: race, sex, name, face morphs, presets, head parts, hair colour | `NPC_` change of the player base `0x7` |
| Known spells, faction ranks | The same `NPC_` change |
| Level, experience | The header |
| Place and facing | Player location table, and a move of the player's reference `0x14` |
| Inventories and worn items | Each reference's inventory change: the count minus the plugin's baseline, worn items marked with extra data type 22 |
| Globals and the clock | Global variable table. The clock writes `GameDaysPassed` and the calendar globals |
| Disabled and deleted references | Form flags `0x800` and `0x20` over the plugin's own record flags |
| Moved references | A move to the reference's own cell or worldspace, and its scale |
| Created references | A created form with the base and the place in its initial data |
| Quest running, completed, and stages done | `QUST` change: flags `0x1` and `0x2`, and each stage as done |
| Alias fills | Extra data type 136 on the filled reference |
| Said topic infos | `INFO` change with the said-once flag |
| Script variables | Papyrus table: one instance per script, with every variable of its script chain |

A form gets the short kind 1 ref id when it is in `Skyrim.esm`, and an index into the form
id array otherwise. A plugin with the ESL flag, or the `.esl` extension, goes in the light
plugin list and gets the `0xFE` id of a light plugin.

## Written empty

A save the game reads must hold every global data table. OpenSky does not model most of
them, so it writes each one as its smallest valid content, from the UESP pages of each
table: zero counts, null ref ids, and empty lists.

| Table | What the empty content means |
| --- | --- |
| Misc Stats, TES, Created Objects, Effects, Audio, SkyCells | Nothing recorded yet |
| Process Lists, Combat, Interface, Actor Causes, Detection Manager | No running actors, combats, or menus |
| Location MetaData, Story Teller, Magic Favorites, Player Controls | No data; controls enabled |
| Story Event Manager, Ingredient Shared, Menu Controls, Menu Topic Manager | No data |
| Quest Static Data | Empty lists, and the last byte 1, which UESP says is always 1 |
| Temp Effects, Anim Objects, Timer | No effects, animations, or timers |
| Weather | Null climate and weather, the clock's hour, transition 1 |
| Unknown 104 and Synchronized Animations (1004) | No bytes: UESP gives no layout |

The game then rebuilds the parts it keeps for a running world, such as actor processes,
from the plugins. This is the main risk of the export: the game may not accept a table
that a real save never has empty.

## What is left out

The export report counts each left-out part with its reason. These cannot be written:

- face tint layers and the face texture: the save's face block has no field for them;
- perk points, attribute picks, skill counts, read books, and power cooldowns: the actor
  value data of the save is undocumented;
- stolen marks: ownership extra data is not written;
- quest objective states: UESP does not name their fields;
- location alias fills, and speaker reset days of said topics;
- script instances with an object or array variable. OpenSky keeps no VM handles, and a
  null handle would replace what the plugin's script properties set. The game binds such
  a script fresh from the plugin;
- scripts whose `OnInit` has not run, script state names, and pending update timers;
- a created reference's stack count, and an exterior created reference when the player
  is in an interior: OpenSky keeps no worldspace per created reference, so an exterior one
  takes the player's worldspace;
- every other kind of runtime state, counted under "other state".

## Unconfirmed choices

There is no real save and no Skyrim SE runner on the development machine
([environment](/tools/environment.md)), so no export has been loaded in the game yet.
These choices follow UESP and ReSaver, and wait for that check:

- the location table offsets on the uncompressed base ([ESS](/formats/ess.md));
- form version 78 and change form version 74;
- the 8-byte actor header of an `ACHR` change, written as zeros;
- an actor change that ends after its inventory, with no animation data;
- the extra flag for alias instances, written as `CHANGE_REFR_EXTRA_GAME_ONLY`;
- the Papyrus save file version, written as 1, and the two unknown instance words, written
  as 0;
- the order of a script's variables, taken from the compiled script;
- the header's game date, written as the date line of the game's own menus;
- the empty tables above.

To check an export, copy it into the Windows game's saves folder, load it, and save again
in the game. Then import the game's save in OpenSky and compare the report.
