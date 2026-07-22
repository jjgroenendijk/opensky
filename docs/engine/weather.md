---
type: Subsystem
title: Weather runtime
description: Region/climate weather selection, timed sky/fog/ambient transitions blended
  over the time-of-day input, and published wind for precipitation/grass/particles.
tags: [engine, weather, sky, environment, wind]
timestamp: 2026-07-22T00:00:00Z
---

# Weather runtime

M7.2.2 (core) + M7.2.3 (live region feed, time-of-day slider, acceptance) + M7.4
precipitation output + acceptance. Data-driven exterior weather over the
[weather records](/formats/weather.md)
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

`WeatherStore` is built in the AppDelegate cell provider and handed to the renderer through
`WeatherProviding`.

M7.4 adds stable Clear/Rain/Snow shortcuts for app acceptance. Each shortcut prefers a known
vanilla editor ID (`SkyrimClear`, `SkyrimOvercastRainFF`, `SkyrimStormSnow`), then falls back
to the first editor-ID-sorted WTHR with matching decoded precipitation classification. The
fallback keeps the controls data-driven for non-vanilla data sets.

### Live XCLR region feed (M7.2.3)

The per-cell region feed is now live. `CellScene` carries the built cell's XCLR REGN FormIDs
(`found.cell.regions`, decoded by the Cell parser). `CellStreamer.emitCenterRegionsIfChanged`
reads the current exterior center cell's regions each drive and, when they change, fires
`onCenterRegionsChanged`; `GameViewController` wires that to `Renderer.weather.setRegions`, so
region-weighted selection runs against the cell the camera actually sits in. Same main thread
as the draw loop -> WeatherSystem stays single-thread-owned.

Only a resident exterior center fires: a center that has not streamed in yet is skipped (a
brief loading gap must not drop region weighting), and the interior path returns before the
emit so entering a building leaves the last exterior region set in place (weather is
exterior-only; the exit resumes seamlessly). A changed region set rerolls immediately unless a
weather is forced.

## Transitions

`WeatherSystem` holds a `from`/`to` weather pair and a 0-1 `transitionProgress`. A reroll or
a forced timed change settles the current visual into `from`, sets the new `to`, and resets
progress to 0. `update(deltaTime:hour:)` advances progress by real `deltaTime / duration`
(smoothstepped for the blend), and at 1 collapses `from` onto `to`.

Auto reroll is driven off the time-of-day input, not real time: each `update` accumulates
the forward change in `hour` (midnight-wrapped) and rerolls every `rerollGameHours`
(6 game-hours). A static clock therefore never auto-rerolls — deterministic for tests and
for a paused sky.

`transitionsPaused` stops only cross-fade progress. A forced target may still replace the
pending target at progress 0; weather resolution, renderer frames, and precipitation particle
playback continue. Resume advances the same transition from its frozen fraction.

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
transition. WTHR Rainy/Snow classification resolves to a two-channel precipitation state;
transition blend supplies its intensity. Missing NAM0/FNAM/DALC fields resolve to
zero/disabled rather than throwing. See [precipitation volumes](/rendering/precipitation.md).

## Wind publication

`WindState` = XY unit direction + 0-1 speed + meander range (degrees), from WTHR DATA Wind
Speed / Direction / Direction Range. Blended across transitions as velocity vectors
(`direction * speed`) so opposing winds cross through calm instead of snapping 180 degrees.
Exposed as `Renderer.currentWind` (calm when inactive) for precipitation, particles, grass,
and later audio consumers.

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

Sidebar path `World > Environment > Weather` (`EnvironmentPanelViewController`), controls:

* Enabled (`WeatherEnabledControl`): master A/B. Off resolves no WTHR snapshot and publishes
  calm wind; selection/transition state stays available for re-enable.
* Weather popup (`WeatherControl`): Auto + every selectable weather's editor ID
  (`WeatherStore.selectableWeathers`, sorted by editor ID so vanilla weathers like
  SkyrimClear/SkyrimCloudy/SkyrimFog are findable among the 84). Forces the live weather with
  a timed transition; Auto resumes automatic selection.
* Clear/Rain/Snow buttons (`ClearWeatherControl`, `RainWeatherControl`,
  `SnowWeatherControl`): force stable data-driven acceptance presets with timed transitions.
* Pause transitions (`WeatherTransitionsPausedControl`): freezes only weather blend progress;
  readout appends `paused`. Renderer + precipitation playback continue for inspection.
* Time-of-day slider (`TimeOfDayControl`, 0-24 h) + `TimeOfDayLabel` HH:MM readout: drives
  `Renderer.timeOfDay` live — the "time transitions in-app" surface, and an A/B of the
  time-of-day keyframe blend. Persisted via `TimeOfDaySettings` (UserDefaults trio, mirrors
  `ShadowQualitySettings`; fallback 13:00), applied at renderer creation.
* Readout: current weather, transition blend %, wind speed/heading.

Every control carries an accessibility identifier for UI tests; focus returns to the World
view after each interaction (`refocusGameView`, on slider drag-end so a drag does not fight
the game view for first responder).

## Acceptance evidence (M7.2.3)

`WeatherAcceptanceRealDataTests` (env-gated, one @Test, run via
`sh tools/realtest.sh openskyTests/WeatherAcceptanceRealDataTests/\
forcedWeathersTransitionsAndTimeProduceDistinctFrames()`) renders the FirstRenderCell exterior
scene offscreen (1280x720) against the real Skyrim.esm and asserts pairwise pixel deltas above
1000 changed pixels. Observed (921600 px total):

* Distinct looks (forced instant, 13:00): SkyrimClear vs SkyrimCloudy 585095 px, clear vs
  SkyrimFog 921600 px, cloudy vs fog 921595 px.
* Transition (clear -> cloudy timed, stepped to 0.45 over 37 monotone samples): mid-frame vs
  clear 204770 px, vs cloudy 364563 px — differs from both endpoints, progress monotonic.
* Time of day (SkyrimClear 04:00 vs 13:00): 921600 px.

## Precipitation acceptance evidence (M7.4.2)

`PrecipitationAcceptanceRealDataTests` forces stable clear/rain/snow presets through the live
`WeatherSystem` + renderer path at FirstRenderCell (640x360). It freezes a partial rain
transition while renderer frames continue, resumes to settled rain, cross-fades to snow, then
returns clear and waits for both particle volumes to drain. Observed changed-pixel counts:

* clear/rain 229507;
* clear/snow 230266;
* rain/snow 132802;
* rain/returned-clear 229507.

All exceed the 250 px gate. `World > Environment > Weather` visual check observed rain at
100% with 297 live rain particles; snow target held at blend 0% while paused, resumed to snow
100% with 768 live snow particles, then returned to SkyrimClear 100% with rain/snow counts 0.
Rendered evidence stays gitignored under `logs/` because it contains game-derived pixels.

## Tests

* `WeatherRuntimeTests` (synthetic): time-of-day weights peak/sum/wrap, resolved blend
  endpoints + monotonicity, fog day/night blend, wind blend, region priority/override +
  climate-fallback selection, deterministic + weighted pick, stable precipitation presets,
  and the WeatherSystem instant/timed/pause transition machine.
* `WeatherRecordTests` / `RecordDecoderTests`: DALC keyframes, WRLD CNAM, CELL XCLR decode.
* `RendererWeatherTests` (Metal 4, offscreen A/B): inactive weather reproduces the
  procedural baseline bit-for-bit; a forced synthetic weather repaints the sky; two distinct
  weathers render different skies.
* `WeatherRealDataTests` (env-gated sweep): every vanilla WTHR DALC decodes with in-range
  channels; Tamriel's WRLD CNAM resolves to a decoded CLMT.
* `CellStreamerTests` (region feed, synthetic): the center cell's XCLR set pushes through
  `onCenterRegionsChanged` exactly once, never re-fires on an unchanged center, and a
  region-less center emits an empty set.
* `WeatherAcceptanceRealDataTests` (env-gated, Metal 4 offscreen): the acceptance gate above —
  distinct clear/cloudy/fog looks, a monotone mid-transition frame differing from both
  endpoints, and a time-of-day difference.
* `PrecipitationAcceptanceRealDataTests` (env-gated, Metal 4 offscreen): partial paused rain,
  settled rain/snow, clear return + particle drain, and numeric frame deltas above.
