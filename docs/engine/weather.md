---
type: Subsystem
title: Weather runtime
description: How a weather is chosen for a region or climate, how weathers cross-fade, how the
  time of day blends each weather, and how wind is published.
tags: [engine, weather, sky, environment, wind]
---

# Weather runtime

Exterior weather comes from the [weather records](/formats/weather.md) (`WTHR`, `CLMT`, `REGN`),
the worldspace climate (`WRLD` `CNAM`), and the cell regions (`CELL` `XCLR`). The runtime picks a
weather for the current worldspace. It cross-fades between weathers over time. It blends the four
time-of-day keyframes of each weather by the hour from the [game clock](/engine/game-clock.md).
The result drives the sky colors, fog, directional ambient light, and sun tint.

With no weather data, or no candidate for the worldspace, there is no weather. The renderer then
draws its procedural sky and camera lighting exactly as it would without this system.

## The weather store

The store decodes every `WTHR`, `CLMT`, and `REGN` once, and reads each worldspace's climate and
editor ID. It is built on the setup thread. After that it holds only immutable values, so the
render thread can read it while the cell builder reads the plugin on its own queue.

## Choosing candidates

The candidate pool for a worldspace and the current cell's regions follows the xEdit meaning of
`REGN`:

1. The regions that apply are the cell's `XCLR` regions with a weather area (`RDAT` type 3) whose
   `WNAM` is this worldspace, or is unset. They are sorted by weather priority. The highest wins.
2. The winning region's `RDWT` list is the pool.
3. If that area's override flag is clear, the worldspace climate's `WLST` list is added after it.
   If the flag is set, the region list stands alone.
4. With no region that applies, the pool is the climate list. With no climate, the pool is empty
   and there is no weather.

The pick is a draw weighted by chance, seeded from the worldspace FormID and a reroll counter. So
the same counter always picks the same weather. If every chance is 0, every candidate is equally
likely.

The Clear, Rain, and Snow shortcuts first look for a vanilla editor ID: `SkyrimClear`,
`SkyrimOvercastRainFF`, `SkyrimStormSnow`. If it is missing, they take the first weather, sorted
by editor ID, with the matching precipitation class. So the shortcuts also work with other data.

## Region changes

Cell streaming reports the regions of the exterior cell at the grid center when they change.
Selection then runs against the cell the camera is in. A changed region set rerolls at once,
unless a weather is forced.

Two cases keep the last region set:

- A center cell that has not loaded yet is skipped. A short loading gap must not drop the region
  weights.
- An interior sends no regions. Weather is exterior only, so leaving a building resumes the same
  weather.

## The climate chance global

Each `CLMT` `WLST` entry has an optional `GLOB` beside its chance. No open source says what the
game does with it. UESP lists the field as `formid - Global`, and xEdit names it `'Global'`, both
without a comment.

OpenSky's choice: a global that resolves replaces the entry's chance. An entry with no global, or
a global the data does not define, keeps its written chance. The value is rounded half away from
zero and clamped to 0 or more, because the pick adds the weights.

Replacing was chosen over scaling. A scale factor has no documented neutral value, and a global
that defaults to 0 would silently delete the weather. With replacement the written number is the
fallback and the global is the override, like every other runtime value. Change this if a real
description is found.

The `REGN` `RDWT` global is ignored.

When a global changes, the system rerolls at once, so the weather follows it without waiting for
the next reroll time. See [runtime state](/engine/runtime-state.md).

## Transitions

The system holds a "from" weather, a "to" weather, and a progress from 0 to 1. A reroll, or a
forced change with a transition, stores the current look as "from", sets the new "to", and resets
progress to 0. Each frame, progress grows by the real frame time divided by the duration. The
blend uses a smoothstep of the progress. At 1, "from" becomes "to".

An automatic reroll happens every 6 game hours. The hours come from how far the game clock moved
since the last frame, not from the hour value itself. So:

- Scrubbing forward ages the weather, up to one day per step.
- Scrubbing backward ages nothing.
- A clock that does not move (an offscreen render, the CLI, a paused game) never rerolls.

Pausing transitions stops only the cross-fade progress. A forced weather can still replace a "to"
weather that has not started. Frames and rain and snow particles keep running. Resuming continues
from the same progress.

## Transition duration

`WTHR` `DATA` "Trans Delta" is a float from 0 to 0.25. UESP and xEdit give it no time unit.
OpenSky reads it as a rate: a full cross-fade takes `1 / clamp(delta, 0.02, 0.25)` seconds.

| Delta | Duration |
| --- | --- |
| 0.25 | 4 s |
| 0.1 | 10 s |
| 0.02 or less | 50 s |
| missing or 0 | 10 s |

This is a chosen mapping, not a spec value.

## Time-of-day blend

The hour and the climate's `TNAM` sunrise and sunset windows give four weights: sunrise, day,
sunset, night. They always add up to 1. At most two neighbors are above 0 at once, with smoothstep
ramps at the window middles.

The same four weights blend every field with four keyframes: sky colors, directional ambient, and
wind. So they all change together. Without `TNAM` the windows are 05:00 to 07:00 and 17:00 to
19:00. Timing that does not go forward (for example a sunset before the sunrise) also uses these
defaults.

One resolved weather holds:

- sky colors (`NAM0`): upper, lower, horizon, sun, sun glare, stars;
- fog (`FNAM`): near and far colors, and distances, power, and maximum blended between day and
  night;
- sunlight and ambient colors (`NAM0`);
- the six-direction ambient (`DALC`);
- wind;
- a precipitation state from the rainy and snow classes.

A missing field resolves to zero or "off" and does not throw. Two resolved weathers are blended
by linear interpolation during a transition, and the transition sets the precipitation strength.
See [precipitation volumes](/rendering/precipitation.md).

## Wind

Wind is a unit direction in XY, a speed from 0 to 1, and a range of meander in degrees, from
`WTHR` `DATA`. During a transition it blends as a velocity, direction times speed. So two opposite
winds pass through calm instead of flipping 180 degrees. The renderer publishes the current wind,
calm when there is no weather, for rain, particles, and grass.

## Renderer use

The weather applies only to exteriors. Interiors keep their `CELL` and `LGTM` lighting.

- The weather sky colors drive the sky shader.
- Weather fog, ambient, sun tint, and directional ambient replace the camera fallback values.
- The sun direction still comes from the time of day. The weather sets only its color.
- The sky shader keeps its procedural sun disc and glow, tinted by the sun and sun glare colors.
  With no weather, it takes the original procedural path.

## Clouds

Each enabled cloud layer of the current weather draws on its shape of the cloud dome
([weather record](/formats/weather.md)). A layer is skipped when its index is at or past `LNAM`,
when `NAM1` disables it, or when it has no texture. Its colour and alpha blend from `PNAM` and
`JNAM` by the same time-of-day weights as the sky. During a transition both weathers' layers
draw, each faded by its share of the blend.

The texture moves by the layer speed per second, in texture repeats, and wraps at one repeat.
[WARNING] The unit of the speed is a guess from the xEdit conversion; the game may scale it.

The dome draws right after the sky, with alpha blending and no depth writes, at the far end of
the depth range. The dome and the textures load off the main actor; until they land, the sky
draws without clouds. Interiors draw no clouds.

## Controls

World > Environment > Weather:

- Enabled: turns the weather on and off. Off gives no weather look and calm wind. The selection
  state stays for when it is turned on again.
- Weather: Auto, or any weather by editor ID. Choosing one forces it with a transition. Auto
  returns to automatic selection.
- Clear, Rain, Snow: force the shortcut weathers above, with a transition.
- Pause transitions: freezes only the blend progress.
- Time of day: a slider from 0 to 24 hours. It sets the game clock hour through the `GameHour`
  global, so the change is journaled and the clock stays the one source of the time. The value is
  kept between runs, with 13:00 as the default.
- Clouds: draws the cloud layers, on by default.
- Readout: the current weather, the blend percent, the wind speed and heading, and how many cloud
  layers draw.
