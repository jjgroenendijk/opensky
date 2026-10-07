---
type: Subsystem
title: MetalFX upscaling
description: How the renderer draws the 3D scene at a lower size and lets the MetalFX
  temporal scaler rebuild the full frame, the conventions it depends on, and how to check it.
tags: [rendering, metal4, metalfx, performance]
---

# MetalFX upscaling

Upscaling draws the 3D scene at a smaller size, the input size, and lets MetalFX rebuild the
frame at the display size, the output size. Two MetalFX scalers can do it:

- The temporal scaler uses earlier frames. Each frame moves the camera by a sub-pixel
  offset, the jitter, so over a few frames the scaler sees more detail than one small frame
  holds. It also smooths edges, as temporal anti-aliasing does.
- The spatial scaler uses the current frame alone. It needs no jitter, motion, or history,
  and costs less, but it keeps the jagged edges of the input.

Reference: Apple, "MetalFX" framework documentation (`MTLFXTemporalScalerDescriptor`,
`MTL4FXTemporalScaler`), and the WWDC 2022 session "Boost performance with MetalFX Upscaling".

## The render scale

The render scale is the input size as a share of the output size: off, 50, 59, 67, 75, 85,
or 100 percent. Off draws at full size and creates no scaler. 100 percent keeps the size but
still runs the scaler, which then works as temporal anti-aliasing. MetalFX on Apple silicon
upscales at most two times on each axis, so 50 percent is the lowest choice.

The player settings `rendering.renderScale` and `rendering.upscaler` store the choices, so the
next launch starts with them. Upscaling is off by default, because on the M1 it measured
slower than native rendering (see When it pays). `Developer > Rendering Performance > Upscaling`
writes the settings, and a change there applies on the next frame. The launcher's Graphics
page writes the same settings before the game starts.

## When it pays

Upscaling saves only the work that grows with the pixel count: the scene's fragment shading
and the image-space grade. Shadow maps, vertex work, and culling cost the same at any size.
The scaler itself costs time at the output size. On a small GPU with a light scene, the
scaler can cost more than the smaller scene saves. On the M1 at 2560 x 1600, the benchmark
view took 7.84 ms of GPU time native, 11.93 ms with the temporal scaler at 67 percent, and
8.71 ms with the spatial scaler at 67 percent. Measure with the benchmark before turning it
on.

## One frame

The steps of a temporal frame. A spatial frame skips the jitter and the motion passes.

1. Before the scene pass, the renderer picks this frame's jitter from a Halton sequence in
   bases 2 and 3, eight frames per cycle, and shifts the projection by it. Frustum culling
   uses the unshifted projection.
2. The scene and its image-space grade draw into the input-size color and depth targets.
3. A motion pass writes a motion vector per pixel: where the pixel was in the last frame. A
   full-screen pass gets it from depth and the camera alone. A second pass redraws each
   moving object with this frame's and last frame's matrices (and bone poses for skinned
   meshes), because camera motion alone would leave a moving object smeared.
4. The scaler reads color, depth, and motion and writes the output-size color.
5. A composite pass copies that into the frame target. The SWF menus and the UI then draw on
   top at full size, so text stays sharp.

## Conventions

MetalFX takes jitter and motion in its own units, and Apple's documentation does not pin
the signs down. OpenSky checked each sign choice against native frames of the same pose,
in `RendererUpscaleTests`. The other choices lost 2 to 8 dB of peak signal-to-noise ratio
(PSNR).

| Input | OpenSky passes |
| --- | --- |
| Jitter | The offset in input pixels, x right and y down, as the projection was moved |
| Motion | Last frame's texture position minus this frame's, in texture units |
| Motion scale | The input size, so MetalFX reads the motion in pixels |
| Depth | Not reversed: near is 0, far is 1 |

## History resets

The scaler forgets its history when the scene swaps, the output size changes, the render
scale changes, or the camera cuts. A cut is a move of more than 1024 units or a turn of more
than 60 degrees in one frame. Without a reset, the first frames after a cut would show a ghost
of the old view.

## Limits

- A moving shadow on still ground lags a little: the ground pixel has no motion, so the
  scaler blends in the old shadow for a few frames. A reactive mask could fix it.
- Particles and other blended effects draw before the scaler and have no motion of their own.
- A GPU without the chosen MetalFX scaler shows the reason in the panel and draws at full
  size. So does a size MetalFX refuses.
- The spatial scaler rejects an sRGB input with a non-sRGB output, so its output uses the
  scene's color format. The temporal scaler writes 16-bit float.

## Checking it

`Developer > Rendering Performance > Upscaling` has the render scale (`RenderScaleControl`)
and the scaler (`UpscalerControl`), and a readout (`UpscalingStatsLabel`): the input and
output sizes and the history resets. `make benchmark ARGS='--render-scale 67'` measures the
GPU time against a native run, and `--upscaler spatial` picks the other scaler
([benchmark](/tools/benchmark.md)).
