---
type: Subsystem
title: Sleep and wait
description: The wait menu and the rest menu, when the game refuses them, and what passing
  time does.
tags: [engine, menu, time]
---

# Sleep and wait

The Wait key (T) opens the wait menu. Using a bed opens the same menu as the rest menu. The
player picks 1 to 24 hours, and the [game clock](/engine/game-clock.md) moves forward by that
much. `openskycli game debug rest <hours> [--sleep]` passes time the same way without the
menu and without its refusals. An NPC's Sleep package lies down in a bed
([furniture](/engine/furniture.md)).

## Refusals

The menu does not open in some states. The HUD then shows the refusal text from a game
setting. The settings are listed on the Creation Kit wiki page "Category:Settings"
(<https://ck.uesp.net/wiki/Category:Settings>). The rest menu uses `sNoSleep...` and the wait
menu `sNoWait...`. OpenSky checks them in this order:

| Reason | Setting suffix |
| --- | --- |
| A script turned waiting off (`SetInChargen`) | `Default` |
| The cell or its worldspace has the Can't Wait flag | `InCell` |
| In combat, or a hostile actor nearby | `HostileActorsNear` |
| Guards are pursuing the player | `WhileAlarm` |
| A guard has told the trespassing player to leave | `WarnToLeave` |
| The player stands in a cell they may not enter | `Trespass` |
| The bed belongs to someone else (sleep only) | `InOwnedBed` |
| Not on the ground | `InAir` |
| A harmful effect drains health each second | `TakingHealthDamage` |

## Passing time

The clock moves in steps of 15 game minutes. Each step ages the [weather](/engine/weather.md)
and runs the scripts' game-time timers, so `OnUpdateGameTime` and a weather change can happen
during a rest. After the last step, OpenSky refills health, magicka, and stamina, and makes an
autosave (`rest` or `wait`). Actors do not move on with their packages during the skipped
time, and timed effects do not run out.

A bed's owner comes from the same ownership rule as theft ([crime](/engine/crime.md)). A bed
the player owns, or that the player's faction owns at a rank they hold, is allowed.

The Can't Wait flag is record-header flag `0x80000` on CELL and on WRLD (UESP
"Skyrim Mod:Mod File Format/CELL" and ".../WRLD"). The order of the first two rows is
OpenSky's reading. Sleeping sends the Papyrus sleep events ([registrations](/engine/papyrus-registrations.md#sleep)).
The Well Rested and Lover's
Comfort bonuses are not given.

## The movie

`Interface\sleepwaitmenu.swf` owns the hours slider and its keys. The engine calls the
root `InitExtensions` and `SetPlatform`, then two functions on `/SleepWaitMenu_mc`:

| Call | Arguments |
| --- | --- |
| `SetSleeping` | true for "Rest how long?", false for "Wait how long?" |
| `SetCurrentTime` | the date line, such as "Sundas, 1:00 PM, 17th of Last Seed, 4E 201" |

The movie calls `OK(hours)` or `Cancel`. The date line uses the weekday and month names
from UESP "Lore:Calendar" (<https://en.uesp.net/wiki/Lore:Calendar>).

Without the movie, OpenSky draws a text panel: A and D change the hours, and Enter waits.
