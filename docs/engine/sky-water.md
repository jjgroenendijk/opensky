---
type: Subsystem
title: Sky + water environment
description: Procedural exterior sky and flat per-cell water from plugin defaults.
tags: [engine, rendering, sky, water, environment]
timestamp: 2026-07-18T00:00:00Z
---

# Sky + water environment

Milestone 3.5 adds exterior environment draws to `RenderScene`: one mergeable sky marker
plus zero/one water item per resident cell. Format rules + sources:
[exterior water records](/formats/water.md). Rendering details:
[Metal 4 renderer](/rendering/metal4-renderer.md).

## Sky

Exterior WRLD without DATA `no sky` bit emits `SkyParameters`. Scene composition keeps one
marker if any resident scene has sky. Renderer draws a fullscreen triangle first, before
depth-tested world geometry. Fragment shader produces hardcoded night/day/twilight upper +
horizon palettes and a soft sun disc from `FrameUniforms.timeOfDayHours` (default 13:00).
CLI screenshot accepts `--time-of-day 0...24`; 24 normalizes to 0.

The hardcoded palette is now the fallback path: when weather is active
(`FrameUniforms.weatherSkyEnabled`), `skyFragment` uses the CPU-blended WTHR sky palette
instead — see [weather runtime](/engine/weather.md). Weather off (no data / inactive)
reproduces this procedural path bit-for-bit.

## Water build

`CellSceneBuilder.buildWater` requires exterior CELL DATA `has water`, a grid, and resolved
finite height. CELL overrides resolve against recursive WRLD defaults; WATR colors resolve
through lazy FormID indexes. One cached 4096x4096 CCW quad serves every cell. Model
translation = `(gridX * 4096, gridY * 4096, waterHeight)`. Plane AABB joins cell bounds, so
camera framing + frustum culling include it. Explicit no-water sentinel emits nothing.

`RenderScene(merging:)` concatenates water items; residency dedupes cached vertex/index
buffers. Streaming ownership remains per cell even though mesh storage is shared.

## Render pass

Order: sky -> opaque instances -> terrain -> alpha-test instances -> water. Water has its
own Metal 4 pipeline: straight-alpha RGB blend (`sourceAlpha`, `oneMinusSourceAlpha`),
depth compare `.less`, depth writes off, culling off. Shader mixes shallow/deep WATR colors
by camera distance, reflection color by view-angle Fresnel, then animates low-cost crossed
sine ripples from frame time. Static NIF alpha-blend support remains separate/deferred.

## Verification

Tests render day/night sky into deterministic offscreen targets, assert time changes color,
and compare water over clear vs sky underlays to prove framebuffer blending. Builder tests
cover WRLD defaults, CELL overrides, parent inheritance, no-water suppression, no-sky WRLD,
color propagation, plane placement, bounds, draw count, and residency merge.

Real-install probe 2026-07-18:

* Tamriel (6,-2), 5x5 + distant LOD -> procedural horizon + sun visible.
* `WhiterunExterior17` (5,-4) -> CELL water detected, one plane rendered with terrain.
* Same water cell, 120 frames @ 1280x720 -> avg 1.13 ms, p95 2.06 ms; 33.33 ms gate passed.

Both checks use engine output from read-only external game input; captures stay local.
