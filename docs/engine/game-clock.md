---
type: Subsystem
title: Game clock and calendar
description: Game time driven by the timescale over the Tamriel calendar, why the clock owns
  time and the time globals follow it, and how weather, offscreen renders, and saves use it.
tags: [engine, world, time, calendar, save-state]
---

# Game clock and calendar

The game clock counts game seconds. Each frame it moves by the real frame time times the
timescale. Hour, day, month, and year all come from that one number, through the Tamriel
calendar. The clock drives the time of day, the weather, and AI schedules.

## Sources

From UESP:

- [Lore:Calendar](https://en.uesp.net/wiki/Lore:Calendar): the months, their lengths, and
  24-hour days.
- [Skyrim:Time](https://en.uesp.net/wiki/Skyrim:Time): "The game begins on the 17th of Last Seed
  in the year 4E 201". Game time runs 20 times faster than real time.
- [Skyrim:Console](https://en.uesp.net/wiki/Skyrim:Console): the time globals.
  `set gamehour to` takes a 24-hour float, `gameday` a day of the month from 1, `gamemonth` 1 to
  12 (10 is Frostfall), `gameyear` the year of the 4th era, `gamedayspassed` the running day
  count, and `timescale` defaults to 20 and accepts 0.

UESP needs a browser User-Agent (see [environment](/tools/environment.md)).

The vanilla default of the `GameHour` global is not documented there. OpenSky starts at 13:00.

## One number

The clock's whole state is `totalGameSeconds`, a `Double`: game seconds since 4E 0, 1st of Morning
Star, 00:00. Every other value comes from it, so no two fields can disagree.

It is a `Double` on purpose. The vanilla start is about 6.3e9 seconds after the start of the
calendar. A `Float` there only has steps of about 512 seconds. A `Double` keeps far better than
a microsecond for any session length. The save stores the same `Double` exactly.

Time moves only through one `advance(wallDelta:timescale:)` call, which is plain arithmetic. The
clock never reads a wall clock. The frame time comes from the renderer's pause-aware frame clock.
So the same start and the same steps always give the same clock. A paused frame gives a step of 0,
so a menu freezes game time and resuming causes no jump (see [menu mode](/engine/menu-mode.md)).

Setters change only what they name:

- Setting the hour keeps the date. 24 becomes 0 of the same day.
- Setting day, month, or year keeps the hour, and clamps into the calendar. Day 31 moved into
  Sun's Dawn becomes 28.
- Setting days passed is the exact inverse of reading it. Adding whole days keeps the hour, which
  is how the console global is used to wait.

## Calendar

Months start at 1, as in the Skyrim console. There are no leap years. The lore's rare 29th of Sun's
Dawn is not modelled. So a year is exactly 365 days, and all the math is whole numbers.

| Month | Name | Days |
| --- | --- | --- |
| 1 | Morning Star | 31 |
| 2 | Sun's Dawn | 28 |
| 3 | First Seed | 31 |
| 4 | Rain's Hand | 30 |
| 5 | Second Seed | 31 |
| 6 | Midyear | 30 |
| 7 | Sun's Height | 31 |
| 8 | Last Seed | 31 |
| 9 | Hearthfire | 30 |
| 10 | Frostfall | 31 |
| 11 | Sun's Dusk | 30 |
| 12 | Evening Star | 31 |

Days passed counts from 00:00 on the 17th of Last Seed, 4E 201. UESP says only "days passed since
starting the game". Starting at midnight is OpenSky's choice. It needs no extra state.

## Timescale

`TimeScale` stays a normal global. The renderer reads it on every step, so a runtime change works
the same frame, and a reset restores the plugin value. With no game data, it is 20.

It is clamped to 0 to 10,000. The floor is vanilla's: 0 stops time, and time never runs backwards.
The ceiling is OpenSky's own safety limit. At 10,000, one clamped 0.1-second frame moves at most
about 17 game minutes, so a garbage value cannot skip months in one frame.

## The clock owns time

Vanilla keeps time in global variables, and conditions and scripts read them. So the clock and the
[runtime globals](/engine/runtime-state.md) must be one source of truth. OpenSky's choice: the
clock owns time. The five time globals, `GameHour`, `GameDaysPassed`, `GameDay`, `GameMonth`, and
`GameYear`, are computed from it.

- Reading a time global asks the clock, before any stored override, so an old override can never
  hide the clock. The value is converted to the global's declared type. Reads are computed, not
  stored, because writing `GameHour` every frame would fill the change log.
- Writing a time global moves the clock and stores no override. The write is still logged as a
  global change. It does not fire the global change event, because that would roll new weather on
  every drag of the time slider. With no clock connected (CLI, tests), the write falls back to an
  override, which the clock read still outranks.
- `TimeScale` is not a time global. It is a rate, and stays a normal override.

## Each frame

The clock lives on the renderer, and is written and read on the main thread. Each frame, before
the world tick and weather, the renderer takes one paused-aware frame step, reads `TimeScale` once,
and advances the clock once. The [Papyrus world runtime](/engine/papyrus-world.md) ticks right
after, so a script waiting on game time sees this frame's clock.

The renderer's time of day is the clock's hour. Setting it moves the hour and keeps the date. So the
time slider, the tests, and the shader uniform all keep their meaning. When plugins are loaded, the
slider writes through the `GameHour` global, the same path a script uses.

## Weather

The weather gets the game hours that really passed since its last update. Moving forward counts,
including a forward drag of the slider. Dragging backward counts zero. One step counts at most 24
hours. See [weather](/engine/weather.md).

## Offscreen renders

An offscreen render never advances the clock. The hour holds, no game time passes, the weather
never rolls, and repeated frames are identical. `--time-of-day` in the CLI sets the start hour on
the vanilla date.

## Saving

Two separate things:

- Between app launches, the time slider's hour is kept as a setting and starts the clock. The date
  starts on the 17th of Last Seed each launch.
- In a save, the whole clock is the `CLOK` chunk ([save
  chunks](/formats/opensky-save-world-chunks.md)). A save with no `CLOK` loads the vanilla start.
  Loading a clock also resets the weather's elapsed-time mark, so a restored date does not count as
  months of weather.
