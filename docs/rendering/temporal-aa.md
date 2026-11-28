---
type: Subsystem
title: Temporal anti-aliasing in the game
description: How Skyrim SE jitters the camera and blends a frame with its history - the jitter
  table, the luma-only history, the history weights, the resets, and where the pass sits in the
  frame.
tags: [rendering, anti-aliasing, taa]
---

# Temporal anti-aliasing in the game

Skyrim SE smooths edges with temporal anti-aliasing (TAA): each frame moves the camera by a part
of a pixel, the jitter, and blends the new frame with the frames before it, the history. The
Medium, High, and Ultra presets turn TAA on and FXAA off; the Low preset turns FXAA on and TAA
off. Both can run at once, FXAA first. OpenSky's own path is MetalFX
([upscaling](upscaling.md)); this page holds the game's rules to compare it with.

## Jitter

The jitter comes from a fixed table of the Halton sequence, base 2 for x and base 3 for y, entries
1 to 8:

| Entry | x | y |
| --- | --- | --- |
| 1 | 1/2 | 1/3 |
| 2 | 1/4 | 2/3 |
| 3 | 3/4 | 1/9 |
| 4 | 1/8 | 4/9 |
| 5 | 5/8 | 7/9 |
| 6 | 3/8 | 2/9 |
| 7 | 7/8 | 5/9 |
| 8 | 1/16 | 8/9 |

A counter steps by one each rendered frame, wrapping after 8, before the entry is read. It starts
at 0, so the first frame uses entry 2. The offset in pixels is `h − 0.5`, so within ±0.5 pixel.
In clip space it is `(2h − 1) / width` and `(2h − 1) / height`, with the current render size, so
the jitter follows a dynamic resolution. With TAA off the offset is 0 and the counter stands
still. The jitter does not stop in a pause or a menu while the world still draws behind it.

## The blend

The game keeps no colour history. Between frames it keeps, per pixel:

- the history luma, with luma `(R + 2G + B) / 4`;
- a thin-feature count;
- the pixel's speed: its motion in pixels divided by 128, kept within 0 ... 1.

Each pixel then runs these steps:

1. **Motion.** The motion vector comes from the nearest surface of the 3×3 pixels around it, by
   depth. The history is read bilinearly where the pixel was last frame.
2. **Unjitter.** The current colour is a 4-tap tent filter of the centre pixel and the three
   pixels on the side the jitter points to. Each tap weighs `max(0, 1 − |distance in pixels|)`
   per axis; this is plain bilinear weighting.
3. **History colour from luma.** Among the 9 current pixels, take the one with the smallest luma
   at or above the history luma and the one with the largest luma below it. The history luma is
   clamped into that range, and the history colour is the blend of the two colours at that luma.
   Two lumas within 0.01 of each other blend half and half. So the history colour always comes
   from the current 3×3 pixels.
4. **Reject.** A previous position outside the screen, or a pixel of an effect mask above 0.1,
   uses the current pixel alone.
5. **Speed change.** With `Δ` the change of the stored speed, `a = max(0, 1 − 20Δ)` and
   `b = max(0, 1 − 100Δ)`. They reach 0 at about 6.4 and 1.3 pixels of change. The current colour
   moves from the unjittered colour toward the raw centre pixel by `a`.
6. **Weight.** The history weight `w` goes from 0.8 at rest to 0.5 at 128 pixels or more of
   motion per frame, then is at most `a`. The thin-feature count times `b` pushes it toward 0.99.
   The result is `current + w × (history − current)`, kept within 0 ... 1. At rest that is 80%
   history and 20% current.
7. **Sharpen.** The result moves 0.21 away from the unjittered colour, then 0.21 back toward it.
8. **Store.** The new history luma blends the same way with `w`. A change below 0.01 stores the
   current luma instead.

A pixel is thin when fewer than 4 of its 8 neighbours have a luma within 0.2 of its own. The count
is `0.95 × last + 0.25 × thin`, kept within 0 ... 1. From 0.9025 the history luma is no longer
clamped. So a still, thin, high-contrast detail holds its history much harder than 0.8.

Example: a still edge pixel whose history luma is 0.6, with neighbours of luma 0.4 and 0.7, keeps
the luma 0.6 and gets a colour two thirds of the way from the 0.4 neighbour to the 0.7 one.

## Resets

A reset clears the history to zero. It happens at the first use after start, and when the loading
screen opens and when it closes. Nothing else resets it: not a camera cut, not a switch between
first and third person, not a menu, and not a large camera move. The only guard against motion is
per pixel, in the steps above. Objects drawn inside a menu keep their own history.

## Order in the frame

1. Full-screen effects: the world map, refraction, FXAA, depth of field, one more, radial blur,
   full-screen blur, and the hit effect.
2. A copy, or the HDR pass.
3. TAA.
4. Depth of field, radial blur, full-screen blur, and the hit effect, when they are held back
   until after TAA. That is the default.
5. Upscaling from the dynamic-resolution size to the screen size, when the two differ.

## Where OpenSky differs

- OpenSky hands the jitter, motion, and history to MetalFX, which keeps a colour history and
  resets it on a camera cut. On a still image the edges change from frame to frame, while the
  game's luma history with its thin-feature hold keeps them still.
