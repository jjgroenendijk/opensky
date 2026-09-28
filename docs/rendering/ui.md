---
type: Subsystem
title: Screen-space UI layer
description: The 2D overlay drawn over the finished 3D frame - anchored scene model, points to pixels
  scaling, CoreText and SWF glyphs in one coverage atlas with eviction, and the single premultiplied
  draw call.
tags: [rendering, ui, metal, text, layout]
---

# Screen-space UI layer

The UI overlay is the last thing drawn in the scene encoder, after precipitation. So the window and
the offscreen renderer both get it with no extra pass. The game's menus are vanilla SWF movies,
drawn by the [SWF layer](/rendering/swf-layer.md) through the same atlas and blend. The overlay draws
after the SWF layer, so developer readouts stay on top.

## Model

- Geometry is plain float math with no device: points, sizes, rectangles, insets, a nine-point
  anchor (corners, edges, center), and a vertical stack with spacing and alignment.
- Scale is one points-to-pixels factor: the user's preset times the display's backing scale,
  clamped to 0.5 to 4. Each rectangle edge and glyph origin snaps to the pixel grid, so lines stay
  sharp at fractional scales.
- A scene is a value: a list of nodes, each an anchor, an offset in points, and content (a panel
  with a border, a marker, or a label). Resolving a scene at a viewport size and scale gives a draw
  list in pixels. The same scene, size, and scale always give byte-identical vertices.
- The draw list has filled rectangles, stroked rectangles, and glyph quads, 6 vertices per quad.
  Solid quads sample a reserved white texel in the atlas, so one pipeline draws everything.

## Text and the glyph atlas

System text uses CoreText in regular and bold. Shaping uses `CTLine` glyph runs, measures
typographic bounds, and wraps greedily at a width in points.

Each glyph is drawn once per font, glyph, and pixel size, through a `CGContext` with font smoothing
off, because smoothing would make output depend on the machine. It goes into one `r8` coverage atlas
packed on the CPU in shelves. The atlas has a revision number that changes on every pack, so the
texture uploads only when it changed.

SWF glyphs go into the same atlas. A decoded SWF glyph becomes a `CGPath` with even-odd fill and is
drawn by the same code. The cache key has a source, system or SWF, so an SWF glyph never collides
with a system glyph that has the same number. Callers keep SWF font keys unique per movie and font.
A missing or undecoded font falls back to the system font. Font decoding is on the
[SWF text](/formats/swf-text.md) page.

The atlas is one fixed-size texture shared by every movie. A host that swaps movies must give cells
back, or the shelves fill and later movies draw no text. So each packed cell keeps its coverage
bytes. Releasing a movie's fonts drops every SWF glyph whose font key matches, then packs the
survivors again from their kept bytes: tallest first, ties broken by a total order on the key, so the
result is deterministic. System glyphs are never released, because the developer UI outlives every
movie. Survivors keep their metrics but move, so callers look them up again each frame. The renderer
releases the old movie's fonts when a new movie is set.

A full atlas drops the glyph and counts it. It never crashes. One movie that needs more than 512 by
512 of coverage still drops glyphs. The atlas is coverage only, so there are no color glyphs.

## GPU path

The overlay has one pipeline with premultiplied source-one-over blending, a depth state that always
passes and never writes, a linear clamp sampler, a shared `r8Unorm` atlas texture, and vertex and
uniform rings with three slots each.

Each frame the scene resolves at the pass's color attachment size, the atlas uploads if its revision
changed, and one draw call runs. The quad budget is 4,096, and the exact number dropped is counted.
The vertex shader maps pixels to normalized device coordinates with a y flip. The fragment output is
premultiplied, `alpha = color.a * atlas.r` and `rgb = color.rgb * alpha`, which matches the blend.
The shared vertex and uniform structs are in `ShaderTypes.h`.

With the overlay off or an empty scene, nothing is drawn. The draw stats count draw calls, quads,
glyphs, and drops, plus atlas size, packed glyphs, occupancy, and pack failures. The atlas numbers
cover both text sources, because the SWF layer packs into the same atlas and draws first.

## Localized sample

The UI Lab has a localized preview. It uses invented `$KEY` strings merged through the real
[translation strings](/formats/translation-strings.md) path: a wrapped paragraph 312 points wide, a
line that runs past the frame edge, and the unknown key `$OPENSKY_UILAB_MISSING`, shown as written.

## Where to see it

`Developer > UI Lab` turns the overlay on and off, shows the plain and localized samples (they share
the one UI scene, so turning on one turns off the other), sets the scale to 50, 100, 150, or 200
percent, and shows the draw and atlas stats. The atlas stats show eviction working: swap movies in
the SWF movie section and the packed glyph count falls back to the new movie's own need instead of
climbing. The same page pushes and pops menus on the real [menu mode](/engine/menu-mode.md)
controller, and shows the translation file and key counts for the install.
