---
type: Subsystem
title: Weather runtime
description: Region/climate weather selection, timed sky/fog/ambient transitions blended
  over the time-of-day input, and published wind for precipitation/grass/particles.
tags: [engine, weather, sky, environment, wind]
timestamp: 2026-07-21T00:00:00Z
---

# Weather runtime

M7.2.2. Data-driven exterior weather over the [weather records](/formats/weather.md)
(WTHR/CLMT/REGN + WRLD CNAM + CELL XCLR). Picks a weather for the current worldspace,
cross-fades between weathers over time, blends each weather's four time-of-day keyframes by
the [sky clock](/engine/sky-water.md) `timeOfDay`, and feeds the result into the renderer's
sky palette + fog + directional ambient + sun tint. Publishes a wind vector for later
precipitation/grass/particle/audio consumers. Impl: `opensky/World/WeatherRuntime.swift`
(value types), `WeatherStore.swift` (index + selection), `WeatherSystem.swift` (state
machine); renderer glue `opensky/Rendering/RendererWeather.swift`.

No weather data, or no candidate for the worldspace -> the runtime resolves nil and the
renderer stays on its procedural sky + camera lighting, byte-for-byte as before weather
existed (verified, below).

## Index + selection

`WeatherStore` decodes every WTHR/CLMT/REGN top group once and reads each WRLD's CNAM
climate + editor ID. Built on the setup thread, then immutable value types only (no ESMFile
retained) -> safe to read from the render thread while the cell builder drives its own
ESMFile copy on the build queue.

`WeatherSelection.candidates` builds the weighted pool for a worldspace + the current
exterior cell's XCLR regions (xEdit REGN semantics):

* Applicable regions = XCLR regions carrying an RDAT weather area whose WNAM is this
  worldspace (or unset), sorted by RDAT weather priority (highest wins).
* Winning region's RDWT list is the base pool. Weather-area Override flag clear -> the
  worldspace climate (WRLD CNAM -> CLMT WLST) list is appended as lower-priority
  candidates; Override set -> the region list stands alone.
* No applicable region -> the worldspace climate list. No climate -> empty -> nil weather.

`WeatherSelection.pick` is a `chance`-weighted draw with a deterministic `SplitMix64` seed
(worldspace FormID + reroll epoch), so a given epoch always picks the same weather (tests
depend on it). All-zero chances fall back to a uniform pick.

Live wiring feeds the worldspace climate path; the per-cell XCLR region feed is not yet
pushed from the streamer (region selection is fully implemented + unit-tested via
`setRegions`, deferred live to 7.2.3). `WeatherStore` is built in the AppDelegate cell
provider and handed to the renderer through `WeatherProviding`.

## Transitions

`WeatherSystem` holds a `from`/`to` weather pair and a 0-1 `transitionProgress`. A reroll or
a forced timed change settles the current visual into `from`, sets the new `to`, and resets
progress to 0. `update(deltaTime:hour:)` advances progress by real `deltaTime / duration`
(smoothstepped for the blend), and at 1 collapses `from` onto `to`.

Auto reroll is driven off the time-of-day input, not real time: each `update` accumulates
the forward change in `hour` (midnight-wrapped) and rerolls every `rerollGameHours`
(6 game-hours). A static clock therefore never auto-rerolls — deterministic for tests and
for a paused sky.

### Trans Delta interpretation (deviation flagged)

WTHR DATA Trans Delta is a 0-0.25 float; its exact game time-unit is not documented in the
open specs consulted (UESP, xEdit label it "Trans Delta" with no unit). OpenSky interprets
it as an inverse rate: a full 0->1 cross-fade takes `1 / clamp(delta, 0.02, 0.25)` seconds
(delta 0.25 -> 4 s, 0.1 -> 10 s, floor -> 50 s). Absent/zero delta -> a 10 s default. This
is a chosen sane mapping, not a spec value; revisit if a real time-base surfaces.

## Time-of-day blend

`TimeOfDayWeights(hour:timing:)` turns the hour + the climate's CLMT TNAM sunrise/sunset
windows into four weights (sunrise/day/sunset/night) that always sum to 1, with only two
adjacent keyframes non-zero at once (smoothstep ramps at the window midpoints). Applying one
weight set to every four-keyframe field keeps sky colors, DALC directional ambient, and wind
in lockstep across the day. No TNAM timing -> default windows (sunrise 05:00-07:00, sunset
17:00-19:00). Non-monotone modder timing is rejected back to the defaults.

`ResolvedWeather.resolve` produces the blended snapshot: sky-upper/lower/horizon/sun/
sun-glare/stars colors (NAM0), fog near/far colors + day/night-blended distances/power/max
(FNAM), sunlight + ambient colors (NAM0), the six-axis directional ambient (DALC, blended
across its four keyframes), and wind. `ResolvedWeather.blend` lerps two snapshots for the
transition. Missing NAM0/FNAM/DALC fields resolve to zero/disabled rather than throwing.

## Wind publication

`WindState` = XY unit direction + 0-1 speed + meander range (degrees), from WTHR DATA Wind
Speed / Direction / Direction Range. Blended across transitions as velocity vectors
(`direction * speed`) so opposing winds cross through calm instead of snapping 180 degrees.
Exposed as `Renderer.currentWind` (calm when inactive) for M7.3-7.5 precipitation, grass,
particle, and audio consumers.

## Renderer integration

`FrameUniforms` gains `weatherSkyEnabled` + a five-color weather sky palette
(`ShaderTypes.h`). Each frame `updateWeather` advances the system from wall-clock delta +
`timeOfDay` and caches `currentResolvedWeather`. `updateFrameUniforms`
(`RendererScenePass.swift`) applies it exterior-only (`scene.lighting == nil`): weather sky
palette drives `skyFragment` when the scene draws a sky, and weather fog / ambient / sun
tint / directional ambient override the camera-fallback uniforms. Interiors keep their baked
CELL/LGTM lighting untouched. Weather doesn't set the sun direction (still time-of-day) —
only its tint. `skyFragment` keeps its procedural sun disc/glow, tinted by the weather sun +
sun-glare colors; with `weatherSkyEnabled == 0` it takes the original procedural branch
unchanged.

## Verification surface

World > Environment panel (`EnvironmentPanelViewController`): a Weather popup (Auto + every
selectable weather's editor ID) forces the live weather with a timed transition, and a
readout shows the current weather, transition blend %, and wind speed/heading. Selecting
Auto resumes automatic selection.

## Tests

* `WeatherRuntimeTests` (synthetic): time-of-day weights peak/sum/wrap, resolved blend
  endpoints + monotonicity, fog day/night blend, wind blend, region priority/override +
  climate-fallback selection, deterministic + weighted pick, and the WeatherSystem
  instant/timed transition machine.
* `WeatherRecordTests` / `RecordDecoderTests`: DALC keyframes, WRLD CNAM, CELL XCLR decode.
* `RendererWeatherTests` (Metal 4, offscreen A/B): inactive weather reproduces the
  procedural baseline bit-for-bit; a forced synthetic weather repaints the sky; two distinct
  weathers render different skies.
* `WeatherRealDataTests` (env-gated sweep): every vanilla WTHR DALC decodes with in-range
  channels; Tamriel's WRLD CNAM resolves to a decoded CLMT.
