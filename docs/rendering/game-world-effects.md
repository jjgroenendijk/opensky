---
type: Subsystem
title: Game world effects
description: How the game draws rain and snow, region emittance, reference fades and mesh
  detail levels, particle spin and inherited velocity, and lightning bolts, and how it marks
  a location cleared, as a behaviour reference for OpenSky.
tags: [rendering, weather, particles, reference, clean-room]
---

# Game world effects

This page describes game behaviour that OpenSky does not match yet. It is a reference for
building it.

Source: a clean-room read of `SkyrimSE.exe` 1.7.104.0 and the compiled shaders in
`Skyrim - Shaders.bsa`, 2026-11-06. The page holds behaviour only: no code, no names from the
binary, and no setting names. The marks [confirmed], [likely], and [not found] mean the same as
on [game screen effects](/rendering/game-screen-effects.md).

## Rain and snow

OpenSky draws a hand-tuned particle volume around the camera. The game draws a fixed grid of
quads that scrolls [confirmed].

### Record data

The `SPGD` data floats, in order: fall speed, spin speed (degrees per second), size X, size Y,
centre offset minimum and maximum, starting spin range (degrees), subtexture columns and rows,
type (0 rain, 1 snow), box size (4096 by default), and density (0 counts as 1). The texture is
the record's `ICON` path. With no path, a soft smoke texture is used
([environment shading](/formats/environment-shading.md)).

### Geometry

It is built once [confirmed]:

- 1000 particles on a 10 x 10 x 10 grid in the box. The cell size is box / 9. Each particle
  is moved by up to half a cell at random. Edge cells wrap into the box.
- Each particle is a quad with corners at (+-size X, +-size Y), turned by a random angle in
  the spin range.
- The centre offset is `u x (maximum - minimum)` along the turned x axis. The minimum
  [likely] is not added.
- Each quad draws one random subtexture cell.
- There are 10 layers. Each has its own random offset of up to one box on each axis.

### Each frame

- Wind = 500 x the sky's wind speed, along the sky's wind direction, when the sky allows wind.
  Velocity = wind + the fall speed downwards [confirmed].
- The scroll offset moves by velocity x time and wraps by the box size. The spin angle moves
  by the spin speed and wraps at a full turn [confirmed].
- The box centre sits half a box ahead of the camera, along the view [likely].
- A rain streak runs from `p - velocity / 15` to `p`. Snow is a quad that faces the camera,
  scaled by the projection. Rain corners are added in clip space, unscaled [confirmed].

### Density and colour

- A weather draws `ceil(density)` layers, at most 10. Layer `i` has alpha
  `saturate(density - i)` [confirmed].
- Pixel: `rgb = texture rgb x 1/1.2`, `alpha = texture alpha x layer alpha` [confirmed].
- During a weather change with progress `t`, the new weather's density is
  `(t - begin) / (1 - begin) x density` once `t` passes `begin`. The old weather's density is
  `(1 - t / (end + 0.001)) x density`. `begin` and `end` are the weather's fade-in and fade-out
  bytes / 255 [confirmed].
- Roofs hide the rain through an occlusion view of 512 x 512 texels. It looks along the fall
  direction, the normalised velocity, so slanted rain stops at a roof edge [confirmed].

## Region emittance

- Only shapes whose lit shader has the external emittance flag take it [confirmed].
- Their emissive colour is a live link to a colour source [confirmed]:
  - a `LIGH`: the light's colour.
  - a `REGN`: the region's colour, [likely] its map colour `RCLR`.
  - a static with the sky-static flag: the current weather's sky-statics colour (weather
    colour 13), which changes with the weather and the hour.
- The shader colour is that colour times the shape's emissive multiple. No other multiplier
  applies [confirmed]. Region and light colours have no hour or storm logic [likely].

## Reference fades

A placed reference fades out past its fade distance and back in when it comes closer.

### Distances

- A sky-cell reference ends at 150,000 units [confirmed].
- Any other reference, with `r` its bound radius (half the bounding box size if the radius is
  below 0.001) and `g` the loaded grid size in cells [confirmed]:
  - `end = 4096 x g x 0.5 - (4096 x 0.5 + r)`: the distance to the edge of the loaded grid,
    less the radius. A reference that [likely] always loads in the distance uses 10 in place
    of `g`.
  - Without that flag, the end is capped at `10 x r`.
  - `start = 0.6 x end`.
  - If `start < 500`, then `start = 500` and `end = max(1000, end)`.

### Each frame

- `d = distance to the camera x camera factor / type multiplier`. The camera factor is
  [likely] 1 for the game camera; its source was [not found].
- Type multipliers: objects 5, items 3, actors 6, sky cell 1. One fade type uses 0 and never
  fades [confirmed].
- A second set of multipliers per cell kind exists: complex scenes first, then cities, then
  interiors, else 1. All of them are 1 by default [confirmed]. Where they apply was
  [not found].
- Target alpha: 1 inside `start`, hidden past `end`, `1 - (d - start) / (end - start)` between
  [confirmed].
- A hidden reference starts to fade in once the target reaches 0.7. A visible one starts to
  fade out below 0.3. Fade-in takes 1.2 s, fade-out 2 s [confirmed].
- During a load and for 20 rendered frames after it, every reference snaps to alpha 1
  [confirmed]. The screen fades in from black over 1 s, after at least 1.5 s of black
  [likely].

## Mesh detail levels

- Only shapes with mesh detail levels switch [confirmed].
- `scale = 1.2 ^ log2(radius / 256)`. The level 1 and level 2 switch distances are their base
  distances x `scale`, each with a lower clamp [confirmed].
- The base distances are off by default for most shapes. Trees use 2844 for level 1 and 2048
  for level 2 [confirmed].
- A level change cross-fades over 1 s [confirmed].

## Particle spin and inherited velocity

These are the NIF particle modifiers ([particles](/rendering/particles.md)).

- Spin on a new particle: a random axis is uniform on the sphere (`z = cos(theta)`, `theta` in
  [0, pi), and a random turn around `z`). The angle and the speed each get a uniform +-
  variation. With the two-way flag, the speed flips sign with 50 % chance [confirmed].
- Spin each update: `angle += max(dt, 0) x speed`. Above 10 pi the angle resets to 0;
  otherwise it wraps by 2 pi. Negative angles do not wrap [confirmed].
- Inherited velocity: the target node's velocity is its change in position over the last
  update. A new particle adds it with the modifier's chance in percent, times a multiplier
  drawn from `[max(m - m v, 0), m + m v]` [confirmed].

## Lightning bolts

- A bolt of generation `g` has `2^g` segments [confirmed].
- `length = 0.5^g x L + 0.25^g x U(-1, 1) x L variation`, split evenly over the segments
  [confirmed].
- `width = child width multiplier^g x width x 0.5` [likely].
- The midpoint displacement uses the arc offset x `0.5^g`. A branch starts at the midpoint of
  a random segment of its parent [confirmed].
- `V` runs from 0 to 1 along the bolt. With a fade flag, vertex alpha is `1 - i^2 / n^2`. Each
  segment is a quad offset by +- the width [confirmed].
- Each frame the bolt moves its midpoints by an arc offset factor [confirmed].
- When the bolt is rebuilt, it [likely] writes its colour and a strength to a linked light.
- How the generation, branch, and subdivision counts change over time was [not found].

## Location cleared

- A location keeps two flags: cleared, and was ever cleared. Setting cleared also sets was
  ever cleared, and clearing it later does not reset that one [confirmed].
- The Papyrus `SetCleared` call sets the cleared flag directly [confirmed].
- The cleared dungeon music and the clearable location keyword are default objects
  [confirmed].
- Whether a disabled or deleted boss counts as dead, and whether the keyword is checked before
  the cleared music plays, were [not found].
