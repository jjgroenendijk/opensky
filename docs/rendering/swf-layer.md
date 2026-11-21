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
pass just before the [screen-space UI](/rendering/ui.md) overlay, so that overlay stays on top.
Tag decoding and frame 1 rules are on the [SWF container](/formats/swf.md) and
[SWF display list](/formats/swf-display-list.md) pages. There is one main movie and an optional
[overlay movie](#overlay-movie).

## The movie package

A package is built once when a movie is assigned:

- Every shape in the dictionary is cut into triangles and put in one static vertex buffer in twips,
  with a table of runs, one per fill.
- Bitmaps upload as `rgba8Unorm` textures, and keep the decoder's premultiplied-alpha flag.
- Gradient fills are baked into a ramp atlas, one 256-texel row per fill, mixed in the
  gradient's interpolation mode ([SWF shapes](/formats/swf-shapes.md#gradients)).
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
turned back to straight alpha), linear, radial, or focal radial gradient with the gradient's
spread mode, or glyph coverage. It does this in straight alpha and applies the color transform.

Every colour a movie holds is a gamma value: shape colours, bitmaps, gradient stops, and the
colour transform's terms. The shader applies the transform to the gamma value, then turns the
result linear (power 2.2), because the window's colour target encodes linear values on write.
Without that step every mid-tone draws too bright. For example, the inventory tints its
category column with multiply 0.66 and add 0.34 while the item list has focus. Its black
background at 60% alpha then turns into grey 0.34 at 60% alpha: about 54 of 255 over a dark
scene, as in the game. Written out without the step, the same pixel came out at 125.

Flash blends gamma values too, so the blend runs in the shader, not in the pipeline. The shader
reads the colour already in the target, which holds linear values, turns it into gamma, and
blends there: the source colour times its alpha, plus the target times one minus that alpha.
Blend mode add adds the source colour times its alpha instead. The result goes back out linear.
For example, black at 60% alpha over a scene at gamma 0.5 gives 0.4 x 0.5 = 0.2. A blend of
linear values gave 0.32, which drew translucent parts too light. Apple GPUs read the target in
the fragment shader at little cost, and the layer draws with one sample per pixel.

## Filters and blend modes

A `PlaceObject3` filter list and blend mode apply to every draw of the object's subtree. The layer
has no offscreen pass, so it draws each effect as extra copies of those draws:

- A drop shadow or glow draws copies under the object. Each copy has the colour transform's red,
  green, and blue multipliers set to zero and the filter colour added, so it is a flat silhouette.
  Its alpha is the object's alpha times the filter alpha times the strength, at most 1.
- A drop shadow moves its copies by the distance, along the angle: an angle of 45 degrees points
  down and to the right. The distance is in stage pixels, 20 twips each.
- A blur of 1.5 pixels or more spreads 8 copies on an ellipse whose radii are half the blur on each
  axis. Each copy is faded so that the 8 together reach 0.99 alpha where they all overlap. A blur
  filter does this to the object itself; a shadow or glow does it to its silhouette.
- A shadow with `CompositeSource` clear draws only the shadow, not the object.
- An inner shadow and a knockout shadow are not drawn. The object still draws.
- Blend mode 8, add, draws with a shader that adds the colour times its alpha to the target
  instead of blending over it. Every other blend mode draws as normal.

Masks inside the subtree stay where they are: a moved copy is cut by the same mask as the object.

Vanilla frame 1 places 234 drop shadows and 4 blurs, and no other filter. Every shadow is an outer
one that draws its object, with a blur of at most 2 pixels and a distance of at most 3. It sets
blend mode 2, layer, 19 times, and 8, add, 6 times (`openskycli swf sweep`).

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

## Layers

The renderer draws three movies, in this order:

1. The HUD layer: `hudmenu.swf`, which stays loaded under every menu
   ([HUD](/rendering/hud.md#the-hud-layer)). The HUD Opacity setting fades only this layer, and a
   loading screen hides it.
2. The menu layer: the main movie, which the open menu's movie takes.
3. The overlay, below.

The HUD layer has its own package and its own running movie, as the overlay does.

## Overlay movie

Some game menus show two movies at once. The book menu draws its pages from `book.swf` and its
button bar from `bookmenu.swf` ([books](/engine/books.md#the-button-bar)). The overlay is that
second movie:

- It has its own package and its own running movie, built when it is set and freed when it is
  cleared.
- It draws after the main movie, with the same fit to the viewport and scale.
- Setting or clearing the main movie leaves it alone. The menu that set it clears it.
- It takes no pointer input.

## Determinism

Drawing is a pure function of the command stream and the viewport. Nothing in the layer reads a wall
clock or a frame counter. The movie moves only when the engine ticks it, so a movie nobody ticks draws
the same bytes every frame. Input is injected, not read, so the same events always give the same
frame. `setInterval` fires from the tick, not a clock, and `Math.random` uses a seeded generator
for the same reason.

## Known visual gaps

- Filters are drawn as copies, not as a real blur, so a wide blur shows steps. Bevel, gradient
  glow, gradient bevel, convolution, and colour matrix filters are not drawn, and neither are inner
  and knockout shadows. Blend modes other than add draw as normal. ActionScript `filters` and
  `blendMode` are not read.
- A glyph is rasterized upright at the text's even scale, then its quad turns, slants, and
  stretches with the transform. A strongly stretched or slanted glyph is sampled from that upright
  picture, so it looks softer than a glyph drawn at its own shape.

## Checking it

Across all 53 vanilla movies, `openskycli swf render-sweep` renders frame 1 with no failures. Many
vanilla menus are blank at frame 1, because their top-level content starts at alpha zero until
ActionScript shows it ([SWF container](/formats/swf.md)). Captures stay in `.logs/`, because they
contain game art.
