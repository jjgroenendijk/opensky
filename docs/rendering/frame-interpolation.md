---
type: Subsystem
title: MetalFX frame interpolation
description: How the renderer builds one extra frame between every two real frames with the
  MetalFX frame interpolator, how it paces the two frames, and what it costs in input lag.
tags: [rendering, metal4, metalfx, performance]
---

# MetalFX frame interpolation

Frame interpolation builds one extra frame between every two real frames. The display then
shows twice as many frames as the game renders. The main use is a high-refresh display, such
as a 120 Hz ProMotion screen: the game renders 60 real frames a second and the screen shows
120.

Reference: Apple, "MetalFX" framework documentation (`MTLFXFrameInterpolatorDescriptor`,
`MTL4FXFrameInterpolator`, `MTLFXFrameInterpolatorBase`).

## When it runs

- It is off by default, because it adds input lag (below). The player setting
  `rendering.frameInterpolation` stores the switch.
- It needs the temporal upscaler at any render scale, 100 percent included
  ([upscaling](/rendering/upscaling.md)). The interpolator reads the scaler's depth and
  motion vectors, so it uses the same jitter and motion conventions. With the render scale
  off, or with the spatial scaler, the panel says what it needs and nothing is built.
- A GPU without the Metal 4 frame interpolator
  (`MTLFXFrameInterpolatorDescriptor.supportsMetal4FX`) keeps the switch off and disabled,
  and the panel and the launcher say why. The M1 supports it.
- If MetalFX refuses an interpolator for a size, upscaling goes on without it and the panel
  shows the reason.

## One frame

1. The scene, motion, and temporal scaler run as for upscaling. The scaler writes this
   frame's color at the output size.
2. The interpolator reads last frame's scaler output, this frame's output, depth, and motion,
   and writes the frame halfway between them.
3. A composite pass draws the built frame into a second drawable. The SWF menus and the UI
   draw on top of it again, so text stays sharp instead of being interpolated.
4. The real frame is drawn into the view's own drawable, as without interpolation.
5. The built frame is presented first. The real frame follows one display interval later
   (`present(afterMinimumDuration:)`).

The scaler's output texture and a history texture swap each frame, so last frame's output
stays intact without a copy. The history resets with the upscaler's history: on a scene
swap, a camera cut, or a size change.

## Pacing

While it runs, the view asks for half the display's refresh rate
(`NSScreen.maximumFramesPerSecond`), and each real frame shows two images. Without
interpolation the view keeps MTKView's default of 60 frames a second.

## Input lag

The built frame needs the next real frame, so every real frame shows later than without
interpolation:

- one display interval, because the built frame shows first;
- plus the interpolator's GPU time;
- and the real frame rate is half, so input waits longer for the next frame.

The panel measures the time from the start of a real frame to the moment it shows on screen
(`addPresentedHandler`), with interpolation on and off, so the two can be compared on any
display.

## Checking it

`Developer > Rendering Performance > Frame Interpolation` has the switch
(`FrameInterpolationControl`) and a readout (`FrameInterpolationStatsLabel`): the frames
built, the real and shown frame rates, and the input-to-screen time. The launcher's Graphics
page has the same switch (`GraphicsFrameInterpolationControl`).
`openskycli game state frame` reports the same numbers under `interpolation`, so the lag can
be measured from a script.
`make benchmark ARGS='--render-scale 100 --frame-interpolation'` measures the GPU time of
both frames ([benchmark](/tools/benchmark.md)).
