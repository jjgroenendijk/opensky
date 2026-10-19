---
type: Subsystem
title: Cell reset
description: When a cell the player left returns to its plugin state, what resets, and what
  is kept.
tags: [engine, world-state, papyrus]
---

# Cell reset

A cell the player left long enough ago returns to its plugin state when the player enters it
again. Source: the Creation Kit wiki page "Cell Reset"
(<https://ck.uesp.net/wiki/Cell_Reset>).

## When a cell resets

When a cell stops being resident, OpenSky stores the game hour on the player, one entry per
cell. When the cell next joins the world for the first time, the entry is used up. The cell
resets when the time away is at least:

| Case | Setting | `Skyrim.esm` value |
| --- | --- | --- |
| The cell's location is not cleared | `iHoursToRespawnCell` | 240 (10 days) |
| The cell's location is cleared | `iHoursToRespawnCellCleared` | 720 (30 days) |

A location is cleared when a script called `SetCleared` on it (the `cleared` flag of
[script state](/engine/papyrus-script-state.md)). The location is the cell's `XLCN`.

A cell does not reset when its encounter zone (`CELL XEZN`) has the ECZN "Never Resets" flag
(`DATA` flags bit 0x01). An exterior cell with no zone of its own uses the worldspace's
`WRLD XEZN`.

The departures are saved in the `CRST` chunk
([save chunks](/formats/opensky-save-world-chunks.md#crst-cell-resets)).

## What resets

For each reference in the cell, OpenSky drops these runtime changes: death, actor values,
combat state, inventory, open state, lock, deletion, position, relocation, harvest, and
tempered copies. So a creature respawns with full health, a container refills, a door shuts
and locks again, a taken item is back, and a harvested plant grows back
([interaction](/engine/interaction.md#grow-back)). A refilled container holds plain copies
again, so the quality of the tempered copies left in it is gone.

These are kept, as the wiki lists:

- The enable state.
- A reference created at runtime, such as one from `PlaceAtMe`.
- A reference with the REFR or ACHR header flag 0x40000000 ("No Respawn").
- An actor whose base has no ACBS "Respawn" flag (bit 0x08).
- A container whose base has no CONT "Respawns" flag (`DATA` flags bit 0x02). A plain chest
  keeps what the player put in it.

Quest-alias protection is not modelled: a quest item in a chest that resets is lost.

## Scripts

A reset reference's scripts start again with fresh variables. `OnInit` runs again, then
`OnReset` (<https://ck.uesp.net/wiki/OnReset_-_ObjectReference>). The wiki says the order of
`OnReset` and `OnCellLoad` is undefined; OpenSky queues `OnReset` after the attach events.

## Sidebar

World > Runtime State > Reset shows how many cells wait to reset and the last reset. "Make
cell resets due" moves every stored departure back, so each cell resets on the next visit.
