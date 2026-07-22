---
type: Architecture
title: Precipitation volumes
description: WTHR-driven camera rain/snow volumes, wind, roof occlusion, storm sky darkening, and app inspection.
tags: [rendering, precipitation, weather, particles, collision, metal]
timestamp: 2026-07-22T00:00:00Z
---

# Precipitation volumes

M7.4 adds exterior rain + snow plus its force/pause/clear acceptance path without a separate
effect engine. Renderer owns two camera-following `ParticlePlayback` objects; they use the shared
[particle simulation + Metal billboard pass](/rendering/particles.md), generated streak/
flake masks, alpha blending, depth test, three-frame instance buffers, and weather wind.
Impl: `PrecipitationVolume.swift`, `RendererPrecipitation.swift`,
`PrecipitationRoofOcclusion.swift`; WTHR feed in `WeatherRuntime.swift`.

No game texture is bundled or extracted. Both small masks are generated into Metal textures
at renderer setup.

## Weather feed + storm sky

WTHR DATA exposes a classification, not an independent precipitation-density scalar:
Rainy -> rain 1, Snow -> snow 1, Pleasant/Cloudy/none -> zero. `PrecipitationState` blends
rain + snow contributions across the existing timed weather transition. Transition progress
therefore supplies intensity and permits a rain/snow cross-fade without a type snap.

Settled intensity feeds emission. Shared NIF fallback rate caps its base at 60 births/s;
large weather volumes multiply rain by 6 and snow by 4 before the simulator's capacity clamp.
These density multipliers are OpenSky visual policy, not claimed Creation Engine constants.
Wind uses `Renderer.currentWind`; rain accelerates more strongly than drifting snow.

`ResolvedWeather.applyingStormSkyDarkening` attenuates sky-upper/lower, horizon, sun, and
glare by up to 35% at full rain/snow intensity. Authored fog, sunlight, ambient, and DALC
stay unchanged. Clear/non-precipitating weather stays byte-identical on this path.

## Camera volume + lifetime

Rain emits downward through a 2,200 x 2,200 x 700 unit box; snow uses a
2,400 x 2,400 x 900 unit box with slower fall, longer lifetime, and more direction
variation. Emitter anchor sits 600 units above camera. Camera movement translates both
emitter transforms and all live particles by the same delta -> stable local density with no
trail left behind during free-fly or walk motion.

Renderer owns both playbacks outside `RenderScene`, so cell recomposition cannot reset a
storm. Buffers/textures join renderer residency for its full lifetime. Interior/no-sky scenes
and disabled precipitation clear live particles + skip draws. A transition back to clear
sets birth rate to zero; existing particles age out normally.

## Roof occlusion

Active precipitation casts one upward ray from camera eye to 4,096 units through resident
static collision. Broadphase queries a narrow vertical AABB from each cell BVH. Narrowphase
tests placed triangle soups, convex hull faces, and boxes exactly, two-sided; curved shapes
use their world AABB as a conservative fallback. Any hit suppresses + clears the camera
volume until ray opens again. This is deliberately simple single-point roof cover; spatial
edge masks and splashes remain later work.

## Verification surface

Sidebar path: `World > Environment`.

* Weather popup can force any decoded WTHR and shows transition progress.
* Weather Clear/Rain/Snow shortcuts select stable decoded presets.
* Pause transitions freezes only weather cross-fade progress; particle playback continues.
* `PrecipitationEnabledControl` is the durable A/B toggle.
* Live readout reports dominant type, blended intensity, rain/snow counts, and `roofed`.

## Verification

`PrecipitationTests` uses synthetic engine values only:

* classification/intensity blend + storm-darkening isolation;
* upward triangle roof hit, lateral miss, and max-distance miss;
* camera-anchor movement, rain/snow births, wind input, and roof suppression;
* shared Metal billboard pass A/B with more than 100 changed channels.

Local env-gated scratch probe (removed before commit per `probe` skill) built
FirstRenderCell from user's read-only Skyrim install, selected decoded WTHR records by
Rainy/Snow classification, and rendered 640x360 A/B captures. Observed:

* `SkyrimOvercastRainFF`: 3,452 changed pixels;
* `SkyrimStormSnow`: 681 changed pixels.

Both captures passed local visual review: distinct rain streaks / snow flakes over the real
cell. PNG + numeric report remain gitignored under `logs/`; they contain rendered game data
and never enter the repo.

M7.4.2 durable acceptance runs `PrecipitationAcceptanceRealDataTests` against FirstRenderCell
at 640x360. The test pauses a partial rain transition while rendering 35 frames, settles rain,
settles snow, then returns clear and waits until both particle counts reach zero. Observed
changed pixels: clear/rain 229507, clear/snow 230266, rain/snow 132802,
rain/returned-clear 229507 (gate: each >250).

Local main-app check at `World > Environment > Weather`: dense rain rendered; snow target
held at blend 0% while paused; resume reached snow 100% with 768 live snow particles; Clear
reached 100% with rain 0, snow 0. Evidence PNGs + report stay gitignored under `logs/`.

## Deferred

* Multi-ray/spatial roof masks, precipitation collision, splashes, accumulation.
* Per-weather density tuning beyond classification + transition intensity.
* Streak geometry/aspect independent from generic square billboards.
