---
type: Subsystem
title: Living environment integration
description: M7 integrated runtime gate, app A/B controls, exterior/interior evidence,
  and combined frame/build/footprint budgets.
tags: [engine, environment, acceptance, rendering, benchmark]
timestamp: 2026-07-22T00:00:00Z
---

# Living environment integration

M7.6 closes living-environment work by running actor animation, cascaded sun shadows,
selected data-driven weather, world particles, precipitation, and grass together. No new
game format or game content lands here. Production render, streaming, app-control, and CLI
paths compose earlier M6/M7 subsystems.

## Runtime seams

Renderer owns independent master A/B switches for animation and weather alongside existing
shadow, particle, precipitation, and grass controls. Disabling animation resets each skinned
mesh palette to its verified bind pose; re-enabling resumes clip playback from renderer time.
Weather off resolves no WTHR snapshot and publishes calm wind. Global renderer time still
advances while animation is off because grass and particle effects share that clock.

World-particle and precipitation enable flags are independent. World particles can be hidden
while WTHR rain/snow remains live, or precipitation can be hidden while cell-owned effects
continue. This separation is both a debugging surface and a deterministic A/B seam.

## App verification surface

Exact sidebar path: `World > Environment`. Durable controls:

* Actor animation: `Enabled`; live playback + updated-bone readout.
* Shadows: `Off / Low / High`; live cascade/caster/update readout.
* Weather: `Enabled`, Auto/forced weather, Clear/Rain/Snow, transition pause, time slider;
  current weather/blend/wind readout.
* Particles: `Enabled`, freeze, emission scale; system/emitter/live readout.
* Precipitation: `Enabled`; rain/snow/intensity/roof readout.
* Grass: `Enabled`, density/distance/wind; scene/draw/cull/drop readout.

Panel remains scrollable. Layout tests pin all controls inside document bounds; UI tests pin
their accessibility identifiers. Enable is the consistent top-level A/B operation. Force,
freeze, tuning, and reset remain separate operations so inspection does not silently mutate
another subsystem.

## Exterior + interior evidence

`LivingEnvironmentAcceptanceRealDataTests` uses the read-only local install and production
builders/renderers. Exterior gate targets Chillfurrow Farm, Tamriel `(7,-3)`, forces
`SkyrimOvercastRainFF` at 13:00, renders each system's A/B plus all-on/all-off, then writes
ignored evidence under `logs/`. Observed:

* 4 animated actors, 408 bind-pose bones after animation A/B;
* 1 world-particle system, 568 grass placements;
* 292 live rain particles, 350 shadow casters, 450 drawn grass instances;
* changed pixels: animation 2, shadows 2, weather 230393, world particles 0,
  precipitation 3082, grass 0, all-on/all-off 230400.

Zero wide-frame pixel delta for world particles/grass means their pixels were not visible in
this distant acceptance camera. Live production counters prove both paths ran; focused
synthetic/real gates in [particle playback](/rendering/particles.md) and
[procedural grass](/engine/grass.md) retain visible A/B evidence.

Interior gate targets Chillfurrow Farm `00016204`. Production build found 1 animated actor +
1 applicable particle system; 12 particles were live, no precipitation ran, and exact-time
animation frames differed by 5 pixels without crash. Local PNG inspection confirmed exterior
rain/overcast vs clear all-off frames and the interior actor pose change. Captures remain
gitignored because they contain game-derived pixels.

## Combined fly budget

`bench --fly-path` now requires a rainy preset and collects peak live-system evidence while
driving production 5x5 streaming. It fails when selected weather, updated actor bones, live
world particles, live rain, shadow casters, or drawn grass is absent. Existing exact actor,
stream, collision, grass-drop, and footprint gates stay active.

Observed Debug gate, 640x360, 2026-07-22:

| gate | observed | budget |
| --- | --- | --- |
| frame | 13.62 ms avg / 23.64 ms p95 | 33.33 ms avg + p95 |
| collision build | 129.83 ms avg / 551.25 ms p95 | 750 ms p95 |
| actor build | 550.55 ms avg / 3014.79 ms p95 | 4500 ms p95 |
| animation update | 1.43 ms avg / 3.20 ms p95 | 4 ms avg + p95 |
| shadow update | 3.87 ms avg / 7.53 ms p95 | 14 ms avg + p95 |
| footprint | 927 MiB peak | 1024 MiB cap + plateau |

Live peaks: `SkyrimOvercastRainFF`, wind 0.098, 445 animated bones, 1305 particles in
58 systems, 306 rain particles, 847 shadow draws/2280 casters, 637 of 12593 grass instances
drawn in 3 calls, zero grass budget drops. Route built exact 35-cell union once, unloaded
9 initial cells, retained 25, and completed 5530 frames.

Full-probe warm-process repeats measured shadow p95 12.13, 12.19, and 13.20 ms. Integrated
cap is 14 ms: 6% above observed worst, below half the 33.33 ms total frame budget.
One warm-process collision repeat reached 723.09 ms p95; 750 ms keeps a measured ceiling
with 3.7% headroom.

## M8 carry-forward

M7 showed one overloaded toggle obscures subsystem state. M8 sidebar convention therefore
requires distinct enable, force, freeze/pause, inspect, and reset actions; live numeric state;
stable accessibility identifiers; scroll/layout tests; deterministic state + pixel-delta
evidence. Milestones extend existing destinations before adding top-level sidebar items.
