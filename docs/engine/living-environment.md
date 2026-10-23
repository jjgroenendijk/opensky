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

## Combined gate

The fly-path gate, `FlyPathGateRealDataTests`, flies through the 5 x 5 streamed world with a rainy
weather forced. It fails if any system is missing: no weather, no updated bones, no live particles,
no rain, no shadow casters, or no drawn grass. It also checks frame time, collision build time,
actor build time, animation and shadow update time, and memory against fixed budgets. The budgets
are in the test. `make test-real PERF=1` runs it ([benchmark](/tools/benchmark.md)).

In a wide exterior view, grass and cell particles can change no pixels, because they are too far
away. Their live counters show they ran. The [particles](/rendering/particles.md) and
[grass](/engine/grass.md) pages have close-up checks.
