---
type: Subsystem
title: Cascaded sun shadows
description: The depth-only cascade pre-pass - cascade fitting and texel snapping, the clamp to
  resident casters, per-cascade caster culling, the hazard barrier, PCF sampling of the sun term,
  quality levels, point light cube shadows, and the fly-path budget.
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

The shadow map is a `depth32Float` array with 3 slices, 2048 by 2048 unless the game's
`iShadowMapResolution` asks for another power of two from 512 to 16384
([graphics options](/engine/graphics-options.md)). The game sets no top size; 16384 is the
largest Metal texture, and its 3 slices take 3 GB. A new size builds a new array while the game
runs; the old one goes once the frames that use it finish. Each cascade gets one
depth-only encoder, cleared to 1. The pre-pass runs on the same command buffer before the scene
pass, in the window and offscreen alike.

Casters are opaque and alpha-test groups, static and skinned, and terrain. Water, sky, and distant
LOD never cast. Alpha-test groups keep their cutout in the shadow (sample the texture, discard), skinned
and morphed ones included, so hair and fur cards cast a cut-out shadow.

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
| High (default) | 3 | `fShadowDistance`, or 12,288 units (3 exterior cells) when it is 0 | 3 by 3 |
| Low | 2 | The high distance, at most 8,192 units | One tap |
| Off | 0 | | The pre-pass is skipped |

Low keeps all 3 slices allocated and draws fewer, so changing quality allocates nothing. The shader's
padding already handles 2 cascades. The on and off switch is separate from quality, so turning shadows
back on keeps the chosen quality.

## Focus shadows

The game's `[Display] iNumFocusShadow` gives up to 4 actors their own sharp shadow map. Behaviour
described from a clean-room read of `SkyrimSE.exe` 1.7.104.0 on 2026-11-06 (only the behaviour was
reported, no code):

- The actors within 450 units of the camera, nearest first, get one map each.
- The shadow is at full strength while the actor is within 225 units, so while the squared
  distance is under a quarter of 450 squared. Past that it falls in a straight line with the
  squared distance, to 0 at 450 units.
- The map is `min(iShadowMapResolution, 50 * 2^max((1800 - d) / 450, 0))` texels a side at
  distance `d`: 800 at the camera, halving every 450 units, 50 at 1,800 units or more.
- The view is orthographic along the sun, `r` to each side of the centre of the actor's bounds,
  where `r` is the bounds' radius. Its eye is `1.1 r` from the centre toward the sun, its near
  plane `0.1 r` and its far plane `2.2 r`.

OpenSky draws each map into the top-left corner of one 1,024 by 1,024 slice of a second depth
array (the same array that holds the
[rain occlusion view](/rendering/precipitation.md#roof-occlusion)). Only actors draw into it,
culled on the CPU, into rings of their own.

The shader takes the darker of the cascade result and every focus map that covers the point, each
blended toward lit by its strength, with a 3 by 3 PCF and a receiver bias of 2 world units.
So an actor's own shadow, and its shadow on the
ground near it, stay sharp where the cascade is coarse. The focus views draw only while the sun
cascades draw.

## Point light shadows

A `LIGH` record with the shadow hemisphere, shadow omnidirectional, or shadow spotlight
type ([CK wiki "Light"](https://ck.uesp.net/wiki/Light)) casts shadows. Each frame the 4
shadow lights nearest the camera each get a cube: six 90-degree depth views of 512 by 512
in one depth array. The distance of a light is measured to its sphere, so a light whose
radius holds the camera counts as 0; a light more than 4,096 units outside its sphere is
skipped. The cubes draw only while shadows are on.

- Faces run +X, -X, +Y, -Y with Z up, then +Z, -Z with Y up. A face looks along its axis.
  Its right vector is `cross(forward, up)`. The near plane is 8 units from the light, and
  the far plane is the light's radius.
- Casters are the same as for the sun: opaque and alpha-test groups, skinned ones, and
  terrain. They go through the auxiliary rings, culled by each face's frustum.
- The scene shader takes the face whose axis is the largest part of the offset from the
  light, and compares one bilinear depth sample. The receiver first moves 2 units along its
  normal against acne. The factor scales only that light's term, on meshes and terrain.

All three shadow types draw as a full cube: a spotlight's cone and a hemisphere's half are
not cut. The reference's `XLIG` shadow depth bias is read but not used. The launcher's
graphics page holds the "Shadows from lights" switch, and `openskycli game debug shadows`
reads how many lights drew a cube in `shadowLights`.

## Choosing the quality

A new renderer starts at high. `openskycli game debug shadows <off|low|high>` changes the tier
until the renderer is rebuilt; nothing saves it.

## Fly-path budget

The fly-path streaming gate (`FlyPathGateRealDataTests`, `make test-real PERF=1`) holds both the
average and the 95th percentile shadow pass time to 14 ms. That is below half of a 30 frames per
second frame (33.33 ms) with some room over measured Whiterun runs. The benchmark tour reports the
`shadows` pass per scene ([benchmark](/tools/benchmark.md)).

## Not done

- A shadow spotlight's cone and a shadow hemisphere's half-space; both draw a full cube.
