---
type: Subsystem
title: Sleep and wait
description: The wait menu and the rest menu, when the game refuses them, and what passing
  time does.
tags: [engine, menu, time]
---

# Sleep and wait

The Wait key (T) opens the wait menu. A bed opens the same menu as the rest menu. The player
picks 1 to 24 hours, and the [game clock](/engine/game-clock.md) moves forward by that much at
once.

## Refusals

The menu does not open in some states. The HUD then shows the refusal text from a game
setting. The settings are listed on the Creation Kit wiki page "Category:Settings"
(<https://ck.uesp.net/wiki/Category:Settings>). The rest menu uses `sNoSleep...` and the wait
menu `sNoWait...`. OpenSky checks them in this order:

| Reason | Setting suffix |
| --- | --- |
| In combat, or a hostile actor nearby | `HostileActorsNear` |
| Guards are pursuing the player | `WhileAlarm` |
| Not on the ground | `InAir` |
| A harmful effect drains health each second | `TakingHealthDamage` |

## Passing time

When the hours pass, OpenSky refills health, magicka, and stamina, and makes an autosave
(`rest` or `wait`). The game instead steps the world hour by hour: actors move on with
their packages, and effects run out. OpenSky does not simulate the skipped hours. Sleeping
sends the Papyrus sleep events ([registrations](/engine/papyrus-registrations.md#sleep)).
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
