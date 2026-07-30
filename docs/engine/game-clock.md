---
type: Subsystem
title: Game clock and calendar
description: Timescale-driven game time over the Tamriel calendar, the clock-owns-time
  authority rule for the vanilla time globals, and the save/journal/UI integration.
tags: [engine, world, time, calendar, save-state]
timestamp: 2026-07-30T00:00:00Z
---

# Game clock and calendar

Issue #164 (milestone M10.2, item 10.2.3) replaces the scrubbed time-of-day float with a
real game clock: game seconds advanced as wall delta times timescale, with hour, day,
month and year derived from the Tamriel calendar. It drives the renderer's time of day and
the weather runtime now, and AI schedules (M16) later. Impl:
`opensky/World/GameClock.swift` (value type), `opensky/Rendering/RendererGameClock.swift`
(per-frame advance and the `timeOfDay` projection).

## Contents

* Spec sources
* `GameClock` — state, precision, determinism
* The Tamriel calendar
* Timescale
* Authority: the clock owns time, the globals project from it
* Ownership, threading, per-frame flow
* Weather: real elapsed game hours
* Offscreen and CLI: a fixed clock
* Persistence: scrub hour and the `CLOK` save chunk
* Tests

## Spec sources

All calendar and time-global facts were confirmed against UESP (fetched 2026-07-28; the
host needs a browser User-Agent, see `docs/tools/environment.md`):

* <https://en.uesp.net/wiki/Lore:Calendar> — month names and lengths, 12 months, 24-hour
  days.
* <https://en.uesp.net/wiki/Skyrim:Time> — "The game begins on the 17th of Last Seed in
  the year 4E 201"; game time passes faster than real time by a factor of 20.
* <https://en.uesp.net/wiki/Skyrim:Console> — the time-global set and semantics:
  `set gamehour to` takes a 24-hour float, `set gameday to` a 1-based day of month,
  `set gamemonth to` 1-12 (10 is Frostfall), `set gameyear to` the 4th-era year number,
  `set gamedayspassed to` the running day count, `set timescale to` defaults to 20 and
  accepts values down to 0.

The vanilla `GameHour` GLOB default is not documented on those pages, so OpenSky keeps its
pre-clock 13:00 default (`TimeOfDaySettings.fallback`) as the start hour rather than
inventing one.

## `GameClock` — state, precision, determinism

`GameClock` is a value type whose entire state is one number, `totalGameSeconds: Double` —
game seconds since the calendar epoch, 4E 0, 1st of Morning Star, 00:00. Hour of day, day
of month, month and year are all derived from it, so no two fields can disagree.

The precision choice is deliberate. The vanilla start moment is about 6.3e9 seconds past
the epoch, where a `Float`'s 24-bit mantissa already quantizes to ~512-second steps; a
`Double` keeps sub-microsecond resolution for any session length. The `CLOK` save chunk
stores the same `Double` bit-exactly ([save container](/formats/opensky-save.md)).

Determinism: `advance(wallDelta:timescale:)` is pure arithmetic and the only way time
moves. Nothing inside `GameClock` reads a wall clock — wall deltas arrive from the
renderer's pause-aware `FrameSimClock` — so a starting state plus a delta sequence always
produces the same clock, which is what the unit tests assert directly. Pausing is not a
clock feature: a paused `FrameSimClock` tick yields a zero delta and moves its own mark,
so menu pause freezes game time and resume carries no jump, for free.

Scrub setters keep everything they do not name: `setHour(_:)` keeps the date (24 wraps to
0 of the same day, matching the slider's upper bound), `setDay`/`setMonth`/`setYear` keep
the hour and clamp into the calendar (day 31 scrubbed into Sun's Dawn lands on 28), and
`setDaysPassed(_:)` is the exact inverse of the `daysPassed` projection, so adding a whole
number of days keeps the hour — the way the console global is used to wait.

## The Tamriel calendar

Per UESP `Lore:Calendar`. Months are 1-based, matching the Skyrim console semantics above
(the Morrowind-era 0-11 indexing documented on the same page does not apply). There are no
leap years; the lore note about an occasional 29th of Sun's Dawn is not modelled. A year
is therefore exactly 365 days and every derivation is pure integer arithmetic.

| # | Month | Days |
| - | ----- | ---- |
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

The vanilla start moment is the 17th of Last Seed, 4E 201. `daysPassed` (the `GameDaysPassed`
projection) counts fractional days from that date at 00:00; UESP documents only "days
passed since starting the game", so zero-at-vanilla-start-midnight is OpenSky's documented
choice, picked because it needs no extra state and makes the setter a trivial inverse.

## Timescale

`TimeScale` stays a real global: the renderer reads it through `GlobalResolution` on every
advance (`Renderer.currentTimescale`), so a runtime override through the #165 layer takes
effect the same frame and a reset restores the plugin default. When nothing resolves it —
no game data, offscreen tests, the CLI — the vanilla default 20 applies.

`GameClock.advance` clamps the value into `0 ... 10 000`. The floor is vanilla's own (0
freezes game time; time never runs backwards). The ceiling is an OpenSky safety bound with
no vanilla equivalent: at 10 000, one clamped 0.1-second frame delta advances game time by
at most ~16.7 game-minutes, so a garbage global cannot skip months in a single frame while
still allowing any plausibly useful fast-forward.

## Authority: the clock owns time, the globals project from it

Vanilla models time as global variables, and conditions and Papyrus read them, so the
clock and the [runtime globals layer](/engine/runtime-state.md) must be one source of
truth. The chosen direction: **the clock owns time**. The five time globals — `GameHour`,
`GameDaysPassed`, `GameDay`, `GameMonth`, `GameYear` — are projections.

* **Reads.** `GlobalResolution` optionally carries a `GameClock`. When it does, a lookup
  whose editor ID classifies as a `GameClock.TimeGlobal` answers from the clock — before
  the override map, so a stale override can never shadow the clock — coerced onto the
  GLOB's declared type. The projection captures the clock at construction; a consumer
  reading time builds a fresh resolution (`WorldStateStore.globalResolution(defaults:clock:)`),
  which is how the acceptance round trip reads mutated time back. Projecting on read was
  chosen over pushing values into the store precisely because a per-frame `GameHour` write
  would spam the journal every frame.
* **Writes.** `WorldStateStore.setGlobal(_:formID:defaults:)` classifies the editor ID and
  redirects a time-global write through `onTimeGlobalWrite`, which the app wires to the
  renderer's clock (`GameViewControllerStreaming.wireGlobals`). The write moves the clock,
  stores **no** override, and journals through the #165 globals ring (old projected value,
  new value, the GLOB's `ReferenceKey`), keeping the causal log intact without a second
  journal shape. It deliberately does not fire `onGlobalMutation`: the clock's motion is
  continuous for its consumers anyway, and firing would reroll the weather on every scrub
  tick. A store with no handler wired (CLI, tests) falls back to a plain override, which
  projection outranks on read, so drift is impossible either way.
* `TimeScale` is excluded from `TimeGlobal` on purpose; it is a rate, not a time, and
  stays an ordinary override.

## Ownership, threading, per-frame flow

The authoritative clock lives on the renderer as `Renderer.gameTime`
(`RendererGameTime`: the clock, its own `FrameSimClock`, the `GlobalResolution` for the
timescale read, and the weather elapsed-hours mark). It follows exactly the threading rule
the old `timeOfDay` float followed: written on the main thread (panel scrubs, global
writes, save restore) and read in `draw(in:)`, which MTKView also runs on the main thread.
Nothing crosses actors.

Per frame, `draw(in:)` calls `advanceGameClockFromWallClock()` before the world-simulation
tick and the weather update: one paused-aware wall delta, one seam read of `TimeScale`, one
`advance`. The [Papyrus VM](/engine/papyrus-vm.md) is ticked immediately afterwards by
`updateWorldSimFromWallClock()`, so a script waking on game time samples this frame's clock
rather than the previous frame's. Every existing
consumer keeps reading `Renderer.timeOfDay`, which is now a computed projection of
`gameClock.hourOfDay`; setting it scrubs the clock's hour and keeps the date, so the
`TimeOfDayControl` slider, the acceptance tests that set `renderer.timeOfDay = 13`, and
the shader uniform all keep their observable meaning unchanged. The app-side slider write
additionally routes through the `GameHour` global when a `GlobalStore` is loaded, so a UI
scrub journals and exercises the same redirect a script write will.

## Weather: real elapsed game hours

`WeatherSystem.update(deltaTime:hour:elapsedGameHours:)` now takes the game hours that
actually elapsed since the previous update. The old `accumulateGameHours(hour:)` wrap
heuristic — reconstructing elapsed time from frame-to-frame deltas of the scrubbed hour —
is deleted along with its state (`lastHour`). The renderer supplies the parameter from
the clock's own motion (`consumeElapsedGameHours()`): forward motion and forward scrubs
count, a backward scrub counts zero, and a single step is capped at 24 hours, preserving
the bounds the heuristic enforced. Details in [weather runtime](/engine/weather.md).

## Offscreen and CLI: a fixed clock

`renderOffscreenFrame` never advances the game clock, so an offscreen render is a fixed
clock by construction: the hour holds, zero game hours elapse, auto reroll never fires,
and repeated frames stay byte-identical. The CLI `--time-of-day` path is unchanged — it
constructs the renderer with an hour, which now seeds a clock at the vanilla date, and
nothing in the offscreen loop moves it.

## Persistence: scrub hour and the `CLOK` save chunk

Two mechanisms, deliberately distinct:

* **Across launches**, `TimeOfDaySettings` keeps persisting the scrubbed hour, which seeds
  the clock at renderer creation. This preserves the pre-clock UX and the Environment
  panel's `isOverridden` semantics unchanged; the date starts at the vanilla 17th of Last
  Seed every launch.
* **In a save**, the whole clock rides the additive `CLOK` chunk
  ([layout](/formats/opensky-save.md)) written from `Renderer.gameClock` beside the world
  snapshot, and a load restores it. An absent chunk — every pre-clock save — restores the
  vanilla-start clock. Setting `Renderer.gameClock` wholesale also resets the weather
  elapsed-hours mark, so a restored date does not register as months of weather time.

The Runtime State panel's own time scrub UI is deferred to the M10.2 acceptance gate
(#166); until then the `World > Environment` slider remains the scrub surface.

## Tests

* `GameClockTests` — vanilla start values and the calendar tables against the cited UESP
  facts; advancement determinism over a delta sequence; timescale scaling and mid-flight
  changes; pause/resume through a real `FrameSimClock` with no jump; defensive clamps
  (negative and non-finite deltas, negative and unbounded timescales); day, month and
  year rollovers; scrub-then-advance; the 24:00 wrap; date-scrub clamping; `daysPassed`
  round trip; `TimeGlobal` classification and projection setters.
* `GameClockGlobalsTests` — the authority rule end to end over a synthetic GLOB plugin:
  reads project from the clock with declared types intact, projection outranks a stale
  override, a `setGlobal` on `GameHour`/`GameYear` moves the clock and stores no override,
  the write journals through the globals ring without firing `onGlobalMutation`, the no-op
  write journals nothing, `TimeScale` still takes the ordinary override path, and a store
  with no clock handler falls back to overrides.
* `OpenSkySaveClockTests` — `CLOK` round trip bit-exactly, byte determinism, absent chunk
  decodes nil, wrong-size and non-finite/negative payloads rejected.
* `WeatherRuntimeTests.autoRerollAdvancesWithElapsedGameHours` — a static clock never
  rerolls; elapsed hours accumulate across updates and reroll at the six-hour cadence.

## Related pages

* [Runtime reference identity and world state](/engine/runtime-state.md) — the globals
  layer and lookup seam the clock projects through.
* [Weather runtime](/engine/weather.md) — the elapsed-game-hours consumer.
* [OpenSky native save container](/formats/opensky-save.md) — the `CLOK` chunk layout.
* [Menu mode](/engine/menu-mode.md) — the pause gate the clock's `FrameSimClock` obeys.
