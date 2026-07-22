---
type: Subsystem
title: Cascaded sun shadows
description: Depth-only cascade pre-pass with per-cascade caster culling clamped to
  resident cells, off/low/high quality, PCF in mesh + terrain fragment paths,
  fly-bench CPU budget, offscreen A/B verification.
tags: [rendering, metal, shadows, engine]
timestamp: 2026-07-21T00:00:00Z
---

# Cascaded sun shadows

M7.1.1 + M7.1.2. Depth-only pre-pass renders casters into a shadow-map array; scene pass
samples it with PCF and darkens only the direct sun term. Standard cascaded
shadow maps ([LearnOpenGL CSM](https://learnopengl.com/Guest-Articles/2021/CSM),
Microsoft "Cascaded Shadow Maps" technique article) — no Bethesda code consulted.

## Cascade fit — `ShadowCascadeMath` (`opensky/Rendering/ShadowCascadeMath.swift`)

* `splitDistances(near:far:count:lambda:)` — practical split scheme:
  `lambda * log + (1 - lambda) * uniform` per split, strictly increasing, last
  pinned to `far`.
* `makeCascades(...)` per cascade slice: 8 world-space frustum corners from
  `cameraToWorld` + fovY/aspect -> light view (`MatrixMath.lookAt` along
  `sunDirection`, up `(0,0,1)`, switches to `(1,0,0)` when sun near vertical) ->
  square ortho extent from slice bounding sphere (rotation-invariant, one-texel
  border) -> origin snapped to texel grid (sub-texel camera motion cannot shimmer)
  -> near plane extended back by `casterBackup` so off-slice casters toward the
  sun still write depth. Returns `ortho * lightView` per cascade.
* `cascadeIndex(viewDepth:splits:cascadeCount:)` — first cascade whose far bound
  contains the fragment's view depth; mirrored verbatim in MSL
  (`sunShadowFactor`, `Shaders.metal`). Padding entries carry the last real bound.
* `MatrixMath.orthographic` added: RH, z to Metal [0, 1], matches `perspective`
  conventions.
* Resident clamp (7.1.2): `makeCascades(... residentBounds:)` limits the
  `casterBackup` near-plane extension to the resident caster set.
  `residentNearLightZ(_:lightView:)` projects the resident world-AABB union into
  light space; `clampedShadowNearZ(sliceNearZ:fullBackupNearZ:residentNearZ:)`
  = `min(sliceNearZ, max(fullBackupNearZ, residentNearZ))` — covers the frustum
  slice, never reaches past resident casters, never exceeds the 7.1.1 backup.
  nil bounds (any unbounded caster) -> unclamped. Streamed cells ARE the caster
  source, so the light volume tracks residency; precision/cost win, no visual
  change.

## Depth pre-pass — `RendererShadowPass.swift`

* Runs on the same reused `MTL4CommandBuffer` before `encodeScenePass`, both call
  sites (`draw(in:)`, `renderOffscreenFrame`). One depth-only encoder per cascade,
  target = slice of a `depth32Float` 2048x2048 x 3 `type2DArray` texture
  (`ShadowConstantCascadeCount`, `ShadowConstantMapResolution`), clear 1, store.
* Casters: opaque + alpha-tested groups (static + skinned) + terrain. Water, sky,
  distant LOD never cast. Alpha-tested groups keep their cutout via
  `shadowAlphaTestFragment` (diffuse sample + discard); skinned cutouts cast
  solid (conservative — see Out of scope).
* Per-cascade per-instance caster culling (7.1.2): for each cascade, only
  instances whose world AABB intersects that cascade's
  `Frustum(viewProjection:)` are drawn (nil bounds -> conservatively drawn).
  Survivors write contiguous runs into a dedicated shadow instance ring sized
  `cascadeCount x` scene instance capacity — one instanced draw per group per
  cascade; the scene pass resets its own cursors to 0 per frame, so sharing its
  ring would collide. `ShadowDrawUniforms` (light view-projection, model
  matrix, cutout params) go to a `cascadeCount x drawCapacity` shadow draw
  ring. Both rings regrow on the scene-pass triggers (`RendererRings.swift`).
* Per-frame accounting: `Renderer.lastShadowDrawStats`
  (`ShadowDrawStats`: draw calls, drawn instances, culled instances, cascades
  rendered) and `Renderer.lastShadowUpdateMS` (CPU wall time of
  `encodeShadowPass`, `lastAnimationUpdateMS` pattern) — culling evidence + the
  fly-bench budget input.
* MTL4 hazard barrier: MTL4 does not auto-track cross-encoder hazards; without
  a barrier the scene pass intermittently sampled the shadow array before depth
  writes landed (~52% of pixels flipped between identical consecutive frames in
  ~half of runs, found by the 7.1.2 determinism test). The final cascade encoder
  issues `barrier(afterStages: .fragment, beforeQueueStages: .fragment,
  visibilityOptions: .device)`, covering all prior cascade encoders.
* Skinned casters bind the same bone-palette slot as the scene pass;
  `frameBonePrepared` guard keeps `prepareBoneMatrices(slot:)` at once per frame
  across both passes.
* Acne control: raster `setDepthBias(2, slopeScale: 3, clamp: 0)`, cull `.back`,
  receiver-side NDC bias 0.0015 in the shader.

## Scene-pass sampling

* `FrameUniforms` gains `shadowViewProjections[3]`, `shadowCascadeSplits`,
  `cameraForward`, `shadowsEnabled`, `shadowInverseResolution`. Argument table
  grows to 1 + 8 + 1 textures (`TextureIndexShadowMap` = 9) and 2 samplers
  (`SamplerIndexShadowCompare` = 1, `compareFunction .less`, linear, clamp).
* `sunShadowFactor` (`Shaders.metal`): view depth = `dot(worldPos - cameraPosition,
  cameraForward)` -> cascade pick (mirror of `cascadeIndex`) -> light-clip
  transform; outside [0, 1] or beyond last split -> lit. PCF via
  `depth2d_array.sample_compare`, tap count driven by
  `FrameUniforms.shadowSampleRadius` (0 = single tap, r > 0 = (2r+1)^2 box; high
  quality = radius 1 -> 3x3). Factor multiplies ONLY the sun lambert term;
  ambient, directional ambient, point lights untouched. Both
  `staticMeshFragment` + `terrainFragment` consume it.

## Quality levels + constants (`RendererSetup.swift`)

`Renderer.shadowQuality` (`ShadowQuality`: `off` / `low` / `high`, default
high):

* high — 3 cascades, `shadowDistance` 12288 (3 exterior cells), 3x3 PCF.
* low — 2 cascades, `shadowDistanceLow` 8192, 1-tap PCF. No shadow-map realloc:
  all 3 slices of the 2048x2048 array stay allocated, low renders fewer; the
  shader's split padding already handles 2 cascades.
* off — pre-pass skipped entirely (zero shadow draw calls).

`casterBackup` 12288 (now clamped to resident bounds), split `lambda` 0.7.
`Renderer.sunShadowsEnabled` stays the independent dev A/B toggle (`H` in the
game view): `shadowRenders = sunShadowsEnabled && shadowQuality != .off`, so `H`
flips shadows without losing the selected quality.

## App surface — `World > Environment`

First sidebar verification surface (AGENTS.md contract): World mode hosts a
collapsible sidebar (`WorldSidebarViewController`, destinations in
`WorldDestination` — future M7.2-7.5 panels append there). Environment panel:
`Sun shadows` popup (Off/Low/High -> `Renderer.shadowQuality`, applied live),
2 Hz stats readout (`lastShadowDrawStats` + `lastShadowUpdateMS`), `H`-toggle
note. Choice persists via UserDefaults key `ShadowQualitySetting`
(`ShadowQualitySettings`; corrupt/missing -> high), applied on renderer
creation incl. the Settings reload path. Accessibility ids tests + later
milestones rely on: `WorldSidebar`, `WorldDestination-<case>`,
`ShadowQualityControl`, `ShadowStatsLabel`. After a popup change the game view
retakes first responder, so WASD/mouse-look resume without a manual click.

## Fly-bench budget (`openskycli bench --fly-path`)

`CellStreamingFlyBenchmarkConfiguration.shadowUpdateBudgetMS` gates shadow avg
AND p95 per frame (`shadowUpdateExceeded` mirror of the animation gate);
`OffscreenBenchResult.shadowMS` collects `lastShadowUpdateMS`. CLI flag
`--shadow-budget-ms`, default 14 ms: original shadow-only Whiterun fly @ 640x360 Debug
measured avg 3.26 / p95 6.52 / max 9.72 ms. M7.6 full-probe warm-process runs measured
p95 12.13/12.19/13.20 ms; 14 keeps 6% measured headroom while staying below half the
33.33 ms total-frame budget.
Report prints `shadow update` + `shadow culling` lines; `tools/probe.sh`
asserts culled casters are reported.

## Verification (2026-07-21)

7.1.1:

* `ShadowCascadeMathTests` (20): splits monotonic/endpoints/lambda blend, ortho
  NDC mapping, slice corners inside cascade NDC, caster-backup depth range,
  texel-grid snapping, up-vector switch, cascade-index boundaries + padding.
* `RendererShadowTests`: synthetic caster/receiver A/B — receiver darkens
  monotonically with shadows on, sky band bit-identical, shadows-off frame
  matches never-enabled baseline.
* Real-data probe (WhiterunExterior06, 1280x720): 5,194 px differ on/off
  (0.56%), 3,370 darker, 0 brighter (no light leak), max luma-sum delta 196,
  shadows-on frame deterministic across renders. 5x5 `screenshot --neighbors`:
  building/wall shadows visible, no acne striping on open terrain.

7.1.2:

* `ShadowResidentClampTests` (7): clamp reduces Z range, never cuts casters
  inside bounds, nil/degenerate bounds safe. `RendererShadowQualityTests` (5):
  off == never-enabled baseline, low + high both darken, each quality
  deterministic across renders (exposed + regression-guards the MTL4 barrier).
  `RendererShadowTests` culling: synthetic in/out-of-frustum instances ->
  culled > 0, drawn < total, image unchanged. `OffscreenBenchResultTests` +
  `CellStreamingFlyPathTests`: shadow metric math + budget error path.
* Real-data quality deltas (WhiterunExterior06, 1280x720): off-vs-high 5,879 px,
  off-vs-low 2,449 px, low-vs-high 5,131 px; off-vs-off and high-vs-high
  bit-identical (0 px). Stats: off 0 draw calls / 0 cascades; low 32 draws /
  53 culled / 2 cascades; high 32 draws / 106 culled / 3 cascades.
* Whiterun fly bench (640x360 Debug, default budgets): shadow update avg
  3.28 ms / p95 6.55 ms / max 17.63 ms vs 12 ms budget; shadow culling 547 draw
  calls, 1,250 drawn, 6,766 culled, 3 cascades; animation avg 1.02 ms vs 4 ms;
  35 unique builds, 9 unloaded, footprint peak 790/1024 MB — all gates green.
* App path recorded at acceptance: `World > Environment > Sun shadows`
  (Off/Low/High). `make test-ui` on the dev machine currently aborts at harness
  init (TCC automation-mode timeout, all UI tests, environment-level); the
  sidebar UI test exists and unit/offscreen coverage stands in.

## Out of scope

Interior point-light shadows (noted for a later milestone), skinned-cutout
alpha discard in the depth pass (still conservative solid).
