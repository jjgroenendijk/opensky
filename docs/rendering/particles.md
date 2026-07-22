---
type: Architecture
title: Particle playback
description: CPU particle simulation, Metal billboard rendering, effect blending, wind input, and app controls.
tags: [rendering, particles, metal, weather]
timestamp: 2026-07-22T00:00:00Z
---

# Particle playback

NIF particle definitions become cell-owned CPU simulations + one instanced Metal draw per
system. Source decode stays in [NIF particle systems](/formats/nif-particles.md); this page
covers runtime behavior. Impl: `ParticlePlayback.swift`, `RendererParticlePass.swift`,
particle entry points in `Shaders.metal`, scene construction in
`MeshLibraryParticles.swift` + `CellSceneBuilderScene.swift`.

Reference for emitter/modifier meaning + `AlphaFunction` values: NifTools `nif.xml`
(<https://github.com/niftools/nifxml/blob/develop/nif.xml>). Runtime policies called out
below are OpenSky choices, not claimed Creation Engine constants.

## Lifetime + ownership

`MeshLibrary` caches immutable `ParticleSystemDefinition` values beside each loaded model.
Every placed REFR receives fresh `ParticlePlayback` state, seeded by FormID + system index.
`RenderScene` owns these playbacks while its cell is resident; scene residency includes
particle instance buffers + effect textures. Cell eviction releases runtime state with the
rest of that scene.

Each playback owns a three-slot shared `MTLBuffer`, one range per frame in flight. Capacity
comes from NiPSysData `BS Max Vertices`, clamped to 2,048 per system before allocation.

## CPU simulation

Simulation is deterministic for a seed + fixed delta sequence:

* Active box, cylinder, sphere, and mesh emitters create world-space particles. Mesh
  emitters currently use their origin because M7.3.1 retains refs, not source vertices.
* Speed, declination, planar angle, color, radius, lifespan, and their variations seed each
  birth. Particles die at lifespan.
* Active modifiers run in serialized order. Gravity updates velocity; wind applies the live
  weather vector times NIF strength; scale interpolates the decoded size curve. Unsupported
  modifiers remain inert + visible in parser diagnostics.
* Radius/alpha fade at birth + death prevents hard pops. Subtexture offsets choose the
  decoded atlas rectangle per particle.

Emitter controller blocks + birth-rate tracks are not decoded yet. Interim OpenSky policy
fills roughly one quarter of capacity per average lifespan, clamped to 6-60 births/s, then
multiplies by user emission scale. Exact-time offscreen renders reset to the stable seed and
step in 50 ms slices, producing repeatable frame-delta tests.

## Billboard draw path

CPU uploads center/radius, color, and UV origin/extent per live particle. `particleVertex`
expands six `vertex_id` corners around each center using `FrameUniforms.cameraRight` +
`cameraUp`; no static vertex/index buffer. `particleFragment` samples effect DDS, applies
scene fog, discards near-zero alpha. Draws depth-test against opaque geometry, never write
depth, cull none.

One pipeline exists per effect blend family:

| NIF source / destination | OpenSky pipeline | Use                 |
| ------------------------ | ---------------- | ------------------- |
| SRC_ALPHA / ONE          | additive         | flame, sparks, glow |
| ONE / ONE                | additive-one     | full-color glow     |
| DEST_COLOR / ZERO        | multiply         | modulation effects  |
| other / absent           | alpha            | smoke, steam, water |

Values are NifTools `AlphaFunction` 6/0, 4/1, and fallback respectively. Pipeline order
follows scene particle order; transparent particle sorting is deferred.

## Weather + controls

`Renderer.currentWind` publishes blended weather direction/speed. Every live frame passes
it into active BSWind modifiers. Calm/no-weather input is zero. Freeze holds simulation +
live count without disabling draws.

Main-app verification: `World > Environment > Particles`:

* Enabled -- draw toggle, simulation state retained.
* Freeze simulation -- stops advancement, keeps current frame.
* Emit 0-200% -- scales new births; existing particles continue.
* Readout -- resident systems, active emitters, live particles, state.

Accessibility IDs: `ParticlesEnabledControl`, `ParticlesFrozenControl`,
`ParticleEmissionControl`.

## Acceptance

Synthetic gates cover deterministic simulation, capacity/lifetime, weather-wind movement,
blend classification, and exact-time Metal frame deltas. Env-gated real-data gate builds
WhiterunWorld cell `(4,-2)`, isolates paired `FlamesTall01` additive fire + `smoke10` alpha
smoke from `fxsmokelargeclose01.nif`, then renders 0.75 s + 1.25 s at 512x512. It requires
both frames nonblank + more than 20 RGB-changed pixels. Numeric stats land in
`logs/particle-acceptance.log`; review frames land in `logs/particles-whiterun-a.png` +
`logs/particles-whiterun-b.png`. Outputs contain user's game content -> gitignored, never
committed.

## Deferred

* NiPSysEmitterCtlr birth rates + interpolators.
* Mesh-surface births, rotation, drag, spawn/death chains, collision, strip particles.
* Back-to-front transparent sorting + soft-particle depth fade.
* Precipitation-specific collision/splashes; camera volumes now consume this path in M7.4.1.
