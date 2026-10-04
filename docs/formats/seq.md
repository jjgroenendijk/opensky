---
type: File Format
title: Start-game quest lists
description: The Data/Seq/<plugin>.seq files that list the quests a plugin starts when a game begins.
tags: [format, quest]
---

# Start-game quest lists

A `.seq` file lists the start-game-enabled quests of one plugin. The game reads it when a
new game or a save loads, and starts every listed quest that is not running yet. The Creation
Kit writes the file; a plugin whose start-game quests are missing from it has quests that
never start in game.

Sources: UESP, "Skyrim Mod:Mod File Format/QUST" (flag 0x0001, Start Game Enabled), and the
Creation Kit wiki, "Generate SEQ File". The layout below was confirmed on the install.

## Location

The file sits in the virtual file system at `seq\<plugin stem>.seq`, such as
`seq\Skyrim.seq` for `Skyrim.esm`. It is a loose file or an archive entry, like any other
data file. A plugin without the file has no list.

## Layout

The file is a bare array of little-endian `uint32` FormIDs. There is no header and no count.
A byte count that is not a multiple of 4 is reported as a truncated list, and OpenSky skips
the whole file.

Each FormID uses the master indexes of the plugin that owns the file, the same way the
plugin's records do. `Dawnguard.esm` has masters `Skyrim.esm` and `Update.esm`, so a FormID
with the top byte `02` names a Dawnguard record.

`HearthFires.seq` breaks this rule. Its 7 quests are `HearthFires.esm` records with the top
byte `02`, but the file writes them with `01`, which the master list maps to `Update.esm`.
The file seems to have been written when `HearthFires.esm` had one master. How the game reads
it is not confirmed. OpenSky reads each FormID through the master list first; when that names
no quest, it uses the same object ID in the plugin that owns the file.

## Observed on the install

| Plugin | Quests |
| --- | ---: |
| `Skyrim.esm` | 330 |
| `Update.esm` | 3 |
| `Dawnguard.esm` | 51 |
| `HearthFires.esm` | 7 |
| `Dragonborn.esm` | 30 |
| `ccBGSSSE001-Fish.esm` | 10 |
| `ccBGSSSE025-AdvDSGS.esm` | 5 |

`ccQDRSSE001-SurvivalMode.esl` and `ccBGSSSE037-Curios.esl` have no file. Every file
decodes with no bytes left over. The runtime use is on the
[story manager](/engine/story-manager.md) page.
