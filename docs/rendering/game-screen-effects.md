---
type: Subsystem
title: Game screen effects
description: How the game draws the image-based lens flare, screen-space reflections, and
  water flow maps, as a behaviour reference for building them in OpenSky.
tags: [rendering, reference, clean-room]
---

# Game screen effects

This page describes how the game draws three effects that OpenSky does not draw yet, or draws
differently. It is a reference for building them.

Source: a clean-room read of `SkyrimSE.exe` 1.7.104.0 and the compiled shaders in
`Skyrim - Shaders.bsa`, 2026-11-06. The page holds behaviour only: no code, no names from the
binary, and no setting names. Each fact is marked:

- [confirmed]: read directly from the program or a shader.
- [likely]: inferred from the code around it.
- [not found]: not located. OpenSky needs a measurement or a choice there.

## Image-based lens flare

Bright parts of the frame bleed into soft streaks along the screen axes. OpenSky shows and
saves the setting, but draws nothing for it.

### Targets

All targets are small float colour targets [confirmed]. `W` and `H` are the frame size.

| Target | Size |
| --- | --- |
| Downsample | W/4 x H/4 |
| Threshold | W/4 x H/4 |
| Near streak chain | W/16 x H/4 |
| Far streak chain | W/32 x H/4 |
| Bloom chain | W/16 x H/16 |

The downsample, near, and far targets are pairs that swap each frame. The other one of the
pair holds the previous frame, the history [confirmed].

### Steps

1. Downsample. Read 4 taps at (+-1, +-1) source texels. Keep the brightest tap by luma
   `0.3 R + 0.59 G + 0.11 B`. With history on, average it 50/50 with the previous frame's
   downsample, read at the pixel's motion vector [confirmed].
2. Threshold, into the W/4 target. A texel is kept only when one of its channels is above 1.
   The output is `saturate(colour) x 0.7` [confirmed].
3. Down to the near width: of 4 horizontal taps at -1.5, -0.5, 0.5, and 1.5 texels keep the
   brightest, then blend 50 % with history [confirmed].
4. The threshold step again with threshold 0 and a lateral repeat, times 0.7. The lateral
   repeat sums the taps at -n to n texels horizontally. Its default is 0, so one tap
   [confirmed].
5. Down to the far width: of 2 taps at +-0.5 texel keep the brightest, then blend 50 % with
   history [confirmed].
6. Near chain: 3 rounds of a horizontal blur of radius 7 and a vertical blur of radius 2. Each
   pass weight is multiplied by `sqrt(0.1)`. The 3 rounds are fixed [confirmed].
7. Far chain: it starts at the far width and runs 3 rounds, vertical then horizontal, with
   weight 1 [confirmed].
8. Bloom branch: a horizontal and vertical blur of radius 2, a brightest-of-4 step with
   history into W/16 x H/16, and another blur. Its weight is `sqrt(intensity)` with an
   intensity of 0 by default, so it is off [confirmed].
9. Combine: the second bloom target into the first, far into near, and near into the bloom.
   The result is added to the HDR scene before tone mapping. The blend is [likely] additive.

### Blur weights

The blur taps sit at whole texels, `i = -r ... r`, at most `r = 7`. The weights are a
normalised Gaussian with `sigma = r / 2`. For `r = 1` they are 0.1065, 0.787, 0.1065. For
`r = 7` the centre weight is 0.1177 [confirmed]. These blurs have no bright pass.

The settings for ghosts, a halo, lens count, dispersal, and colour split exist, but no pass
reads them [likely].

## Screen-space reflections

Shiny surfaces and wet ground reflect what is on screen. OpenSky reflects only on water.

### Mask

The lit shader writes a reflection mask per pixel into a channel of the normal target
[confirmed]:

- `mask = smoothstep(a, b, x) x m`. `x` is the specular mask: the normal map alpha, or on
  terrain the layer blend of it. A shader without a specular map uses 0.
- `a` is about 0.1 and `b - a` is about 0, so by default the mask is close to a step at 0.1
  [likely].
- `m` is a material scale, [likely] 1.

### Trace

- A ray takes at most 16 steps. The last steps sit at 0.875 and 0.9375 of the ray
  [confirmed].
- A ray that faces the camera, leaves the screen, or finds no hit writes 0 [confirmed].
- Colour: `intensity x hit colour + a second input colour`, with an intensity of about 0.8
  [likely].
- Weight: `(1 - hit distance on screen x k) x mask x (1 - min(2 |hit uv - 0.5|, 1)^2)`, so it
  falls off with the ray length and near the screen edge [confirmed].

### Wet ground

A pixel whose wetness channel is at least 0.00001 counts as wet. A wet pixel always reflects:
its mask is at least 1. It reflects with a fixed normal, [likely] up in view space, not with
the surface normal [confirmed].

### Composite

The reflection joins the frame with the weight
`(0.95 - 0.85 x mask) x clamp(250 x (z - near) / (far - near), 0.1, 0.95) x intensity`
[confirmed], where `z` is the pixel's depth.

## Water flow maps

A flow map moves the water normal along a direction that changes over the surface. OpenSky
reads the flow map fields but does not use them ([water](/rendering/water.md)). All facts here
are [confirmed] from the water shader.

- A per-vertex flow scale `s` sets a grid with one cell every `1/(64 s)` in flow map UV. Four
  flow map taps sit `1/(128 s)` apart: (0, 0), (d, 0), (0, d), and (d, d).
- Each tap gives a direction `2 xy - 1`, a speed term `k = sqrt(1.01 - z)`, and a time scale
  `w` from its alpha.
- The normal map UV is the vertex UV x 64 x `k`, turned into the tap's direction. It scrolls
  along the turned x axis by `time x w x c`, plus a fixed offset `o`. The time is the
  shader clock in milliseconds x 0.001 [likely].

| Tap | `c` | `o` |
| --- | --- | --- |
| (0, 0) | 8.0 | 0 |
| (d, 0) | 8.48 | 0.62 |
| (0, d) | 10.64 | 0.27 |
| (d, d) | 9.92 | 0 |

- The four normal samples blend bilinearly with triangle-wave weights
  `wx = 1 - |2 frac(64 s u) - 1|`, and the same for `wy`.
- The sum keeps its contrast: `n.xy = (sum - 0.5) / (sqrt((1 - wx)^2 + wx^2) x
  sqrt((1 - wy)^2 + wy^2))`.
- `n.xy` is scaled by a distance term of at least 0.4, and `n.z` is rebuilt from it.
- The flow normal blends with the normal map normal by
  `saturate((depth - 8192) / (far - 8192))`.
- There is no second time phase that blends two copies.
