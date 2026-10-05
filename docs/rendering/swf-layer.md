---
type: Subsystem
title: SWF render layer
description: How a Scaleform movie's display list is drawn over the 3D frame - the per-movie GPU
  package, letterboxed viewport mapping, counting-stencil clip layers, the shader, the running movie
  path, the determinism rules, and the known visual gaps.
tags: [rendering, ui, swf, metal]
---

# SWF render layer

The SWF layer draws a movie's display list over the finished 3D frame. It is encoded in the scene
pass just before the [screen-space UI](/rendering/ui.md) overlay, so developer readouts stay on top.
Tag decoding and frame 1 rules are on the [SWF container](/formats/swf.md) and
[SWF display list](/formats/swf-display-list.md) pages. There is one SWF layer.

## The movie package

A package is built once when a movie is assigned:

- Every shape in the dictionary is cut into triangles and put in one static vertex buffer in twips,
  with a table of runs, one per fill.
- Bitmaps upload as `rgba8Unorm` textures, and keep the decoder's premultiplied-alpha flag.
- Gradient fills are baked into a ramp atlas, one 256-texel row per fill.
- Text is laid out in twips, so the layout does not depend on the viewport.
- Per-draw uniform rings and glyph vertex rings have three slots. They are sized to the current
  command stream plus half again, at least 64, because a display list that ActionScript changes
  outgrows an exact fit at once.

Setting a movie builds the package on the main thread between frames. The old package's memory is
freed once frames in flight finish. Setting a new movie also stops any running movie, because the
new movie makes the old tree meaningless.

The shared objects are the content and mask pipelines, three depth-stencil states, a repeat sampler
for tiled bitmaps, and 1 by 1 white textures so the bitmap and gradient bindings stay valid on draws
that use neither.

## Encoding

Drawing walks the flat command stream in paint order. Each draw writes one 256-byte-aligned uniform
slot with:

- the combined transform from placement, sprite, movie, viewport, to clip space (twips to pixels to
  normalized coordinates);
- the fill-space transform (bitmap coordinates, or the -1 to 1 gradient square);
- the color transform multiply and add pair;
- the fill mode.

Shapes bind the movie's static vertex buffer. Text binds the per-frame glyph quad ring, laid out
axis-aligned in pixels at the on-screen em size.

The movie's `FrameSize` is fitted into the viewport with one uniform scale and centered, so a
different aspect ratio gets letterbox bars. The renderer's presentation factor, 0.5 to 2, scales that
fit around the same center, instead of pinning the movie to an edge.

## Clip layers

Clip layers use a counting stencil. Starting a clip draws the mask shape with increment-clamp.
Ending it draws the shape again with decrement-clamp. Each content draw passes only where the
stencil equals the number of active clips. So nested and overlapping clip ranges become an
intersection, with no extra passes. The mask fragment writes zero, which leaves color unchanged
under the premultiplied blend, so no color write mask is needed. The scene pass therefore uses
`depth32Float_stencil8`, in the window and offscreen alike.

## The shader

The fragment shader works out solid color, bitmap (clamp or repeat, with a premultiplied source
turned back to straight alpha), linear or radial gradient with the gradient's spread mode, or glyph
coverage. It does this in straight alpha, applies the color transform, then premultiplies for the
blend.

## A running movie

The layer draws frame 1 until something runs the movie's ActionScript. The
[AS2 display runtime](/engine/as2-display-runtime.md) produces the same command stream the static
builder does, so drawing does not change. Only the source of the stream does.

- Starting a movie runs every `DoInitAction`, then frame 1, then its `DoAction` blocks, and pushes
  the display list that made.
- A tick pushes a new stream only when the tick changed something.
- Injected input pushes whatever the movie changed, and answers whether the movie used the event.
- A call into the movie, the engine side of the [GameDelegate bridge](/engine/as2-game-delegate.md),
  pushes the same way. A call can name a display path.
- Several engine changes can be batched and pushed once. A failed GPU update sets the runtime's dirty
  flag again, so the same state can be tried again.
- Stopping drops the runtime and goes back to the static frame 1 stream.

A new stream keeps every static GPU resource: shapes, bitmaps, the gradient ramp, and the glyph atlas.
Only draws, uniforms, and text runs are planned again. The text planner lives across updates, so
atlas keys for imported fonts stay the same. New keys each update would fill the atlas with copies.
Rings grow but never shrink, and a replaced buffer is freed after frames in flight finish, like a
movie swap. Draws past the ring size are counted as skipped, not dropped silently.

Text set at run time reaches the renderer as an override on the scene item, and is laid out again.

## Determinism

Drawing is a pure function of the command stream and the viewport. Nothing in the layer reads a wall
clock or a frame counter. The movie moves only when the engine ticks it, so a movie nobody ticks draws
the same bytes every frame. Input is injected, not read, so the same events always give the same
frame. `setInterval` fires from the tick, not a clock, and `Math.random` uses a seeded generator
for the same reason.

## Known visual gaps

- Line styles are not stroked. Only fills draw.
- A focal radial gradient draws as a plain radial gradient.
- `linearRGB` gradient interpolation is treated as normal RGB.
- `PlaceObject3` filters and blend modes are ignored.
- Glyph quads follow a transform's position and scale, but not rotation or skew. Vanilla UI text is
  not rotated.

## Where to see it

`Developer > UI Lab > SWF movie` lists `None` and every `Interface\*.swf` in the install, turns the
layer on and off, and shows the movie's tag tally, its ActionScript inventory, the draw stats,
unresolved font names, and any load error. The movie list is built once, lazily, because listing
movies walks every archive index. `None` gives the layer back to the gameplay [HUD](/rendering/hud.md).

`Developer > UI Lab > SWF runtime` runs the assigned movie. It has Start, Tick, Tick 20 (a vanilla
menu's open and close animations are each about 20 frames), and Stop. It sends navigation keys, and
pointer moves and clicks at a position in movie stage pixels. It calls a named function: the list is
the movie's own `GameDelegate.addCallBack` names, and it is editable, because some entry points are
root clip functions the delegate does not list (`SetPlatform` and `InitExtensions` in
`tweenmenu.swf`). Readouts show the runtime state, the invoke log, and the tally. Every shortened
list shows its total, so a cut list never reads as complete. No control throws: every failure goes
to the load error the readout shows.

Across all 53 vanilla movies, `openskycli swf render-sweep` renders frame 1 with no failures. Many
vanilla menus are blank at frame 1, because their top-level content starts at alpha zero until
ActionScript shows it ([SWF container](/formats/swf.md)). Captures stay in `.logs/`, because they
contain game art.
