---
type: Subsystem
title: Cascaded sun shadows
description: Depth-only cascade pre-pass over static/terrain/skinned casters, PCF
  in mesh + terrain fragment paths, offscreen A/B verification.
tags: [rendering, metal, shadows, engine]
timestamp: 2026-07-21T00:00:00Z
---

# Cascaded sun shadows

M7.1.1. Depth-only pre-pass renders casters into a shadow-map array; scene pass
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

## Depth pre-pass — `RendererShadowPass.swift`

* Runs on the same reused `MTL4CommandBuffer` before `encodeScenePass`, both call
  sites (`draw(in:)`, `renderOffscreenFrame`). One depth-only encoder per cascade,
  target = slice of a `depth32Float` 2048x2048 x 3 `type2DArray` texture
  (`ShadowConstantCascadeCount`, `ShadowConstantMapResolution`), clear 1, store.
* Casters: opaque + alpha-tested groups (static + skinned) + terrain. Water, sky,
  distant LOD never cast. Alpha-tested groups keep their cutout via
  `shadowAlphaTestFragment` (diffuse sample + discard); skinned cutouts cast
  solid (conservative, revisit with 7.1.2 quality setting).
* Caster instances written ONCE per frame into a dedicated shadow instance ring
  (scene pass resets its own cursors to 0 per frame -> sharing would collide);
  per cascade the whole group culls by merged bounds against
  `Frustum(viewProjection:)` of that cascade, then redraws the recorded range.
  `ShadowDrawUniforms` (light view-projection + model matrix + cutout params) go
  to a `cascadeCount x drawCapacity` shadow draw ring. Both rings regrow on the
  scene-pass triggers (`RendererRings.swift`).
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
  transform; outside [0, 1] or beyond last split -> lit. 3x3 PCF via
  `depth2d_array.sample_compare`. Factor multiplies ONLY the sun lambert term;
  ambient, directional ambient, point lights untouched. Both
  `staticMeshFragment` + `terrainFragment` consume it.

## Constants (`RendererSetup.swift`)

`shadowDistance` 12288 (3 exterior cells; farther casters unshadowed by design
until 7.1.2), `casterBackup` 12288, split `lambda` 0.7, 3 cascades @ 2048.
`Renderer.sunShadowsEnabled` defaults true; game view toggles it with `H`
(dev A/B surface; `World > Environment` quality setting lands in 7.1.2).

## Verification (2026-07-21)

* `ShadowCascadeMathTests` (20): splits monotonic/endpoints/lambda blend, ortho
  NDC mapping, slice corners inside cascade NDC, caster-backup depth range,
  texel-grid snapping, up-vector switch, cascade-index boundaries + padding.
* `RendererShadowTests`: synthetic caster/receiver A/B — receiver darkens
  monotonically with shadows on, sky band bit-identical, shadows-off frame
  matches never-enabled baseline.
* Real-data probe (WhiterunExterior06, 1280x720): 5,194 px differ on/off
  (0.56%), 3,370 darker, 0 brighter (no light leak), max luma-sum delta 196,
  shadows-on frame deterministic across renders. 5x5 `screenshot --neighbors`:
  building/wall shadows visible, no acne striping on open terrain. `bench`
  (single cell) avg 1.73 ms / p95 2.39 ms vs 33.33 ms budget — fly-bench shadow
  budget is the 7.1.2 gate.

## Out of scope (7.1.2+)

Per-cascade caster culling limited to resident cells, explicit fly-bench shadow
budget, off/low/high quality setting + sidebar surface, interior point-light
shadows (noted, later milestone).
