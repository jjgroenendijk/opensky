---
type: Subsystem
title: Living environment
description: How animation, shadows, weather, particles, rain and snow, and grass run together,
  their separate on and off switches, and the combined fly benchmark.
tags: [engine, environment, rendering, benchmark]
---

# Living environment

The living environment is several systems running together in the same frame: actor animation,
sun shadows, weather, world particles, rain and snow, and grass. This page covers how they fit.
Each system has its own page.

## Separate switches

Each system has its own on and off switch in the renderer. Turning one off must not change
another. This makes each one easy to test by comparing frames with it on and off.

- Animation off puts each skinned mesh back in its bind pose. Animation on resumes from the
  renderer clock. The clock keeps running while animation is off, because grass and particles
  use it too.
- Weather off uses no weather and sets the wind to calm.
- World particles and rain or snow have separate switches. Rain can run with cell particles
  hidden, and the other way round.

## Controls

World > Environment has one section per system:

| System | Controls | Live readout |
| --- | --- | --- |
| Actor animation | Enabled | Playback, updated bones |
| Shadows | Off, Low, High | Cascades, casters, updates |
| Weather | Enabled, auto or forced weather, Clear, Rain, Snow, pause transition, time | Weather, blend, wind |
| Particles | Enabled, freeze, emission scale | Systems, emitters, live particles |
| Rain and snow | Enabled | Type, intensity, roof |
| Grass | Enabled, density, distance, wind | Scenes, draws, culled, dropped |

"Enabled" is the same on and off action in every section. Force, freeze, tuning, and reset are
separate actions, so looking at one system never changes another. This rule came from an early
single switch that hid which system was in which state. See
[app UI](/tools/app-ui.md) for the panel rules.

## Combined benchmark

`openskycli bench --fly-path` flies through the 5 x 5 streamed world with a rainy weather forced.
It fails if any system is missing: no weather, no updated bones, no live particles, no rain, no
shadow casters, or no drawn grass. It also checks frame time, collision build time, actor build
time, animation and shadow update time, and memory against fixed budgets. The budgets are in
the benchmark code. See [CLI](/tools/cli.md).

In a wide exterior view, grass and cell particles can change no pixels, because they are too far
away. Their live counters show they ran. The [particles](/rendering/particles.md) and
[grass](/engine/grass.md) pages have close-up checks.
