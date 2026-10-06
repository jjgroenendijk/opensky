---
type: Engine
title: Skyrim Save Import
description: How OpenSky turns a Skyrim .ess save into an OpenSky save, what it brings over, and what it drops.
tags: [save, ess, import]
---

# Skyrim save import

OpenSky can load a save the game wrote. It reads the `.ess` file read-only, maps what it
can onto OpenSky's own world state, and writes the result as an ordinary OpenSky save. Then
it loads that save. So an import and a normal load share one restore path, and an import
is never a second, half-tested way into the world.

The file formats are on their own pages: [ESS](/formats/ess.md),
[ESS change forms](/formats/ess-change-forms.md), and
[ESS Papyrus](/formats/ess-papyrus.md). The OpenSky side is
[OpenSky save](/formats/opensky-save.md).

## The saves folder

The Skyrim saves folder is a setting, like the data root. There is no default path to
probe: a Steam install on macOS has no standard place for Skyrim's saves. The setting is
read in this order:

1. the `OPENSKY_SKYRIM_SAVES` environment variable;
2. `OpenSkySkyrimSavesFolder` in the shared defaults domain, which Settings writes.

The settings page shows one line: not set, missing, has no `.ess` files, or how many saves
it holds. The CLI's `ess list <folder>` prints the same line.

## Where a user meets it

| Place | What it does |
| --- | --- |
| Settings, Skyrim Saves Folder | Pick or clear the folder |
| Load list, in-game and on the title screen | Each `.ess` is a row titled `Skyrim import: <file> - <name>`, with its screenshot. Loading it runs the import |
| Library, Skyrim Saves | Lists the folder and inspects the selected save without importing. Dry Run Import shows the report an import would give |
| `openskycli ess <save.ess>` | The inspection as text, with the import report against the current load order |

Import rows are never written over or deleted, and Continue never picks one. The OpenSky
save an import writes is named `Imported <file>`, so a second import of the same file
replaces it.

## The pipeline

1. Read the file and decode it (`ESSFile`).
2. Build a plugin index for this save, off the main actor (`ESSPluginIndex`). It walks each
   active plugin's record headers once and keeps only what the import checks: the type and
   editor ID of `GLOB`, `QUST`, `INFO`, `RACE`, `SPEL`, `FACT`, `CELL`, `WRLD`, `CONT`, and
   `NPC_` forms. Cell children are walked only when the save changed an inventory, and only
   those references decode their base. It loads the compiled scripts the Papyrus table
   names.
3. Run the import (`ESSImporter`). It is pure: a decoded file and a records port in, the
   contents of an OpenSky save, a report, and the player's place out. It never throws for
   a decoded file; each part that does not map is counted with its reason.
4. Write the contents as an OpenSky save slot, then load that slot.
5. Move the player: to the saved interior by its editor ID, or to the saved position in the
   current worldspace.
6. Show the report's totals as a notification.

## Load order mapping

A save names forms by its own load order. OpenSky maps each one by plugin name, not by
index, onto the load order it runs now. A reordered load order still maps. A plugin the
save used but that is not loaded now is listed in the report, and every form from it is
counted as dropped, never fatal. Light plugins map the same way.

## What maps

| Save data | OpenSky state |
| --- | --- |
| Header level and experience | The player's progression |
| Player name, race, and sex; face morphs, presets, head parts, and hair color | The player's identity |
| Player spells and factions, from the player's `NPC_` change | The spellbook and faction ranks |
| Global variables | Global values, with the type the current `GLOB` declares |
| `GameDaysPassed`, else the calendar globals | The game clock |
| Reference form flags | Enabled or disabled, and deleted |
| Reference moves | A transform override |
| Created references | A spawned reference with a generated key |
| Inventory changes | The inventory: the base container's items plus the save's counts |
| Worn extra data in an inventory | Equipped items |
| Quest stages done and quest flags | Quest running, completed, and stages reached |
| Alias instance extra data | Quest alias fills |
| Topic info said once | The line's said count |
| Papyrus instance variables of type none, int, float, bool, string | Script variables |

The player's placed reference, `Skyrim.esm` `0x14`, maps to OpenSky's player key. Created
forms get generated keys in the order the import first meets them, so one save always
imports to the same keys.

## What is dropped, and why

| Data | Why |
| --- | --- |
| Actor data after the animation part: health, death, actor values, perks | The layout is undocumented ([change forms](/formats/ess-change-forms.md#references)) |
| Base attributes of an `NPC_` change, and anything after them | The layout is undocumented |
| Changes to an actor base other than the player's | OpenSky keeps actor state on the placed actor |
| A reference moved to another cell | OpenSky's transform override cannot move a reference between cells |
| Created items: enchantments, potions, poisons | OpenSky cannot create forms |
| Papyrus object and array values | Their ids belong to the game's VM and mean nothing to OpenSky's |
| Running and suspended stacks | OpenSky's VM cannot resume another VM's half-run function. They are counted per script |
| Script state names | Not documented in the save |
| Quest objectives | The two fields are unnamed |
| Lock state | UESP does not say which lock flag bit means locked |
| Stolen marks from ownership | Not mapped yet |
| Shouts and leveled spells | OpenSky keeps no known-shout or leveled-spell list on the player |
| Face tint layers | The save's face block holds none |

Imported script instances are marked as having run `OnInit`, because the game ran it
before it saved.

## Unconfirmed choices

These follow the plugin formats and UESP, and wait for a real save to confirm:

- quest flags `0x1` running and `0x2` completed, as in plugin `QUST DNAM`;
- the exterior cell of a created reference, as its position divided by 4096;
- the player's heading, taken as the z rotation of the player's reference change.

## Where OpenSky differs from the game

The game keeps a whole running world in its save. OpenSky imports the parts it can name and
reports the rest. An imported game therefore starts with all scripts idle, no actor
remembers damage, and the dead are alive again. The report says how much of each was left
out.
