---
type: Subsystem
title: Cascaded sun shadows
description: The depth-only cascade pre-pass - cascade fitting and texel snapping, the clamp to
  resident casters, per-cascade caster culling, the hazard barrier, PCF sampling of the sun term
  only, quality levels, and the fly-bench budget.
tags: [rendering, metal, shadows, engine]
---

# Cascaded sun shadows

A depth-only pre-pass draws shadow casters into a shadow map array. The scene pass samples it with
percentage-closer filtering (PCF: several depth comparisons averaged) and darkens only the direct sun
term. This is standard cascaded shadow mapping, as described in
[LearnOpenGL CSM](https://learnopengl.com/Guest-Articles/2021/CSM) and Microsoft's "Cascaded Shadow
Maps" technique article.

## Fitting the cascades

- Split distances use the practical scheme: `lambda * log + (1 - lambda) * uniform` per split, with
  lambda 0.7. Splits increase strictly, and the last one is the far distance.
- For each slice, the eight world corners of the camera frustum slice go into light view space. The
  light looks along the sun direction with up `(0, 0, 1)`, or `(1, 0, 0)` when the sun is near
  vertical.
- The extent is a square taken from the slice's bounding sphere, so it does not change when the
  camera turns, with a one-texel border.
- The origin snaps to the texel grid, so camera motion smaller than a texel cannot make shadows
  shimmer.
- The near plane moves back toward the sun, so casters outside the slice still write depth. It moves
  back at most 12,288 units, and never past the box around the resident cells. The loaded cells are
  the only casters, so a longer reach only wastes depth precision. This clamp does not change the
  image. Any caster with no bounds turns the clamp off.

The cascade for a fragment is the first whose far bound holds its view depth. The shader repeats the
same rule. Unused cascade entries carry the last real bound. The orthographic projection is
right-handed and maps z to Metal's 0 to 1, like the perspective projection.

## The pre-pass

The shadow map is a `depth32Float` 2048 by 2048 array with 3 slices. Each cascade gets one
depth-only encoder, cleared to 1. The pre-pass runs on the same command buffer before the scene
pass, in the window and offscreen alike.

Casters are opaque and alpha-test groups, static and skinned, and terrain. Water, sky, and distant
LOD never cast. Alpha-test groups keep their cutout in the shadow (sample the texture, discard).
Skinned cutouts cast solid, which is safe but not exact.

Each cascade draws only the instances whose box meets that cascade's frustum. An instance with no
box is drawn. The survivors go in the shadow pass's own instance ring, sized cascades times the
scene's instance capacity. It cannot share the scene's ring, because the scene pass restarts its
cursor at 0 each frame. Shadow draw uniforms have their own ring too. Both grow when the scene rings
grow. Skinned casters use the same bone palette slot as the scene pass, computed once per frame.

Metal 4 does not track hazards between encoders. Without a barrier, the scene pass sometimes sampled
the shadow array before the depth writes landed: about half of all pixels changed between identical
frames, in about half of the runs. A determinism test found it. The last cascade encoder now issues
`barrier(afterStages: .fragment, beforeQueueStages: .fragment, visibilityOptions: .device)`, which
covers every cascade encoder before it.

Acne control is a raster depth bias of 2 with slope scale 3, back-face culling, and a receiver-side
bias of 0.0015 in normalized device coordinates.

## Sampling

The scene shader computes view depth as `dot(worldPos - cameraPosition, cameraForward)`, picks the
cascade, and moves the point into light clip space. A point outside 0 to 1, or past the last split,
is lit. PCF uses `depth2d_array.sample_compare` with a radius: 0 is one tap, and r gives a
(2r + 1) squared box, so radius 1 is 3 by 3. The result multiplies only the sun Lambert term.
Ambient, directional ambient, and point lights are not touched. Static meshes and terrain both use
it.

## Quality levels

| Quality | Cascades | Distance | PCF |
| --- | --- | --- | --- |
| High (default) | 3 | 12,288 units (3 exterior cells) | 3 by 3 |
| Low | 2 | 8,192 units | One tap |
| Off | 0 | | The pre-pass is skipped |

Low keeps all 3 slices allocated and draws fewer, so changing quality allocates nothing. The shader's
padding already handles 2 cascades. The on and off switch is separate from quality, so turning shadows
back on keeps the chosen quality.

## Where to see it

`World > Environment > Sun shadows` turns shadows on and off and sets the quality. The readout shows
the shadow draw calls, drawn and culled instances, cascades, and the CPU time of the shadow pass. The
quality is saved in user defaults, and a bad or missing value means high.

## Fly-bench budget

`openskycli bench --fly-path` holds both the average and the 95th percentile shadow pass time to
`--shadow-budget-ms`, 14 ms by default. That is below half of a 30 frames per second frame (33.33 ms)
with some room over measured Whiterun runs. The report prints the shadow update time and the culling
counts ([CLI](/tools/cli.md)).

## Not done

- Shadows from interior point lights.
- Alpha cutouts on skinned casters in the depth pass.
