---
type: Subsystem
title: Screen-space UI layer
description: 2D overlay pass over the finished 3D frame - anchored value-type scene,
  layout + text primitives, CoreText system-font glyph atlas, points -> pixels scale
  handling, single premultiplied draw call, plus the SWF display-list render layer.
tags: [rendering, ui, metal, text, layout]
timestamp: 2026-07-23T00:00:00Z
---

# Screen-space UI layer

M8.1.1. Draws as the final commands of the existing scene encoder (after
precipitation) -> drawable + offscreen render paths get the overlay automatically,
no extra pass. Game-UI direction is a vanilla SWF port (issue #99); this layer
remains the screen-space compositing foundation it renders through.

## Model (`opensky/UI/`)

- Geometry: `UIPoint/UISize/UIRect/UIInsets`, 9-point `UIAnchor` (corners/edges/
  center). `UIVerticalStack` stacks rects with spacing + alignment. Pure float math,
  device-free.
- Scale: `UIScale` = one points -> pixels multiplier (user preset x backing scale,
  app-supplied), clamped 0.5-4. Rect edges + glyph origins snap per-edge to the pixel
  grid -> crisp lines at fractional scales.
- Scene: `UIScene` value type; `UINode` = anchor + point offset + content
  (`panel(size:color:border:)`, `marker`, `label`). `resolve(viewportPixels:scale:
  atlas:)` -> pixel-space `UIDrawList`. Resolve is deterministic: same scene + size +
  scale -> byte-identical vertices. `UIScene.labSample` = built-in preview content
  (bordered panel, bold heading, body line, wrapped paragraph, 4 corner markers).
- Text: system font via CoreText (`UIFont` regular/bold). `UITextShaper` shapes with
  CTLine glyph runs, measures typographic bounds, greedy word wrap at a point width.
  Glyphs rasterize once per (font, glyph, pixel size) through CGContext with font
  smoothing off (determinism) into `UIGlyphAtlas`: CPU shelf-packed r8 coverage
  bitmap with reserved white texel; `revision` bumps on pack.
- SWF fonts (M8.2.3): `UIGlyphAtlas.swfEntry(fontKey:glyphIndex:emPixelSize:makePath:)`
  rasterizes a decoded SWF glyph the same way, from a CoreGraphics `CGPath`
  (`SWFGlyphPath.makePath`, even-odd fill) instead of a CTFont glyph — the shared
  rasterizer path packs both into the one r8 atlas, so SWF text draws through the
  same premultiplied screen-space pipeline as system text. The cache key carries a
  `.system`/`.swf` source namespace so an SWF glyph never collides with a system
  glyph sharing the same numeric `fontKey`; callers keep `fontKey` unique per
  (movie, font id). Missing/undecoded fonts fall back to `UIFont` system rendering.
  Font/text/glyph decode lives in [SWF container](/formats/swf.md); the display-list
  render that places these glyph quads is the SWF layer below.
- Draw list: `UIDrawList` immediate-mode builder - `fillRect`, `strokeRect`,
  `addGlyphQuad`; 6 vertices/quad; solid quads sample the white texel so one
  pipeline draws everything.

## GPU path (`Rendering/RendererUIPass.swift`)

- `UIResources` built at init: `ScreenSpaceUI` pipeline (`uiVertex`/`uiFragment`,
  premultiplied source-one over blend), compare-always/no-write depth state, linear
  clamp sampler, shared-storage `r8Unorm` atlas texture, triple-buffered vertex +
  uniform rings (slot-indexed, 256-byte-aligned uniforms). All in `residencySet`.
- `encodeUI(descriptor:state:)` at end of `encodeScenePass`: resolve scene at the
  pass color-attachment size, upload atlas only when `revision` changed (glyph set
  stabilizes after first frame), apply hard budget `uiQuadBudget = 4096` with exact
  drop count, one `drawPrimitives` call. Shader maps pixel coords -> NDC (y-flip)
  from `UIFrameUniforms.viewportSize`; fragment = `color * atlas.r`.
- Shared structs/indices in `ShaderTypes.h`: `UIVertex` (pos/uv/color),
  `UIFrameUniforms`; `BufferIndexUIVertices/UIUniforms`, `TextureIndexUIAtlas`,
  `SamplerIndexUIAtlas`; argument-table counts bumped in `makeArgumentTable`.
- Renderer API: `uiEnabled` (default true), `uiScene` (default `.empty` -> zero
  draws), `uiScale` (default 1), `lastUIDrawStats` (`drawCalls, quads, glyphs,
  dropped, atlasWidth, atlasHeight`).

## SWF display-list layer (M8.2.4)

The SWF layer draws a movie's frame-1 display list over the finished 3D frame,
encoded inside the same scene pass immediately before the dev UI overlay (so
stats and readouts stay on top). Tag decode and the frame-1 semantics live in
[SWF container](/formats/swf.md); this section is the GPU side.

- Movie package (`Rendering/RendererSWFMovie.swift`, `SWFMovieResources`): built
  once per assigned movie. Every dictionary shape is tessellated through
  `SWFShapeCache` into one static twip-space vertex buffer with a per-fill run
  table; bitmap characters upload as `rgba8Unorm` textures (carrying the
  decoder's `premultipliedAlpha` flag); gradient fills bake into a ramp atlas,
  one 256-texel row per fill; text draws are laid out in twips at build time
  (`SWFTextLayout`), viewport-independent. Per-draw uniform and glyph-vertex
  rings are sized exactly for the frame's command stream and triple-buffered.
- Static objects (`Rendering/RendererSWFResources.swift`, `SWFPassResources`):
  the content and mask pipelines (shared `swfVertex`, `swfFragment` vs
  `swfMaskFragment`), the three depth/stencil states, a linear repeat sampler
  for tiled bitmap fills, and 1x1 white fallback textures so the bitmap and
  gradient bindings stay valid on draws that use neither.
- Encode (`Rendering/RendererSWFPass.swift`): walks the flattened command
  stream in paint order. Per draw it writes one 256-byte-aligned
  `SWFDrawUniforms` slot holding the concatenated
  place -> sprite -> movie -> viewport -> NDC transform (twips to pixels to
  clip), the fill-space transform (bitmap uv or the -1..1 gradient square), the
  CXFORM multiply/add pair, and the fill mode. Shape draws bind the movie's
  static vertex buffer; text draws bind the per-frame glyph-quad ring, laid out
  axis-aligned in pixel space at the on-screen EM size.
- Viewport mapping (`SWFViewportMapping`): uniform scale fitting the movie's
  `FrameSize` into the viewport, centered — letterboxed on an aspect mismatch.
  No wall-clock or frame-counter input anywhere in the layer.
- Clip layers use a **counting stencil**: `beginClip` draws the mask geometry
  with increment-clamp, `endClip` repeats it with decrement-clamp, and each
  content draw tests `stencil == active clip count` (the reference value set per
  draw). That handles interleaved and nested clip ranges as an intersection
  without per-clip passes. The mask fragment writes zero, which under the pass's
  premultiplied `one`/`one-minus-source-alpha` blend leaves color untouched, so
  no color-write mask is needed. The scene pass therefore runs on
  `depth32Float_stencil8` (drawable and offscreen paths both).
- Shader (`Shaders.metal`, `swfVertex`/`swfFragment`): resolves solid, bitmap
  (clamp or repeat, unpremultiplying a premultiplied source), linear/radial
  gradient (with the GRADIENT spread mode folded in), or glyph coverage in the
  straight-alpha domain, applies the CXFORM, then premultiplies for the blend.
- Renderer API: `setSWFMovie(_ scene: SWFMovieScene?) throws` (main thread,
  between frames — builds the package synchronously and retires the old one's
  allocations once in-flight frames drain), `swfScene`, `swfEnabled` (A/B
  toggle; off encodes nothing and reproduces the no-movie frame byte for byte),
  and `lastSWFDrawStats` (`SWFDrawStats`: `drawCalls`, `triangles`, `glyphs`,
  `maskDraws`, `skippedItems`). `SWFMovieLoader` turns a VFS path into a
  font-resolved `SWFMovieScene`.
- Determinism: the whole path is a pure function of movie plus viewport, so
  repeated renders are byte-identical (asserted in `RendererSWFTests`).
- Known visual gaps: line styles are not stroked (fills only), focal radial
  gradients render as plain radial, `linearRGB` gradient interpolation is
  treated as normal RGB, PlaceObject3 filters and blend modes are ignored, and
  glyph quads follow a transform's position and scale but not its rotation or
  skew (vanilla UI text is unrotated).

## App surface

`Developer > UI Lab` sidebar destination — the M8.1 foundation acceptance surface
(M8.1.4), talking to the engine through `UILabControlProviding` on
`GameViewController` (bridge split to `opensky/GameViewControllerUILab.swift` for
the file-size limit; weak-provider pattern shared with the Environment panel):

- Overlay enable (`UIOverlayEnabledControl`), lab-sample toggle
  (`UILabSampleControl`), localized-sample toggle (`UIStringsSampleControl` —
  the two samples share `Renderer.uiScene`, so enabling one clears the other),
  scale presets 50/100/150/200% (`UIScaleControl`), live draw-stats readout
  (`UIStatsLabel`).
- Menu-mode preview: Push menu / Pop / Clear buttons (`UIMenuPushControl`,
  `UIMenuPopControl`, `UIMenuClearControl`) drive the real `MenuModeController`
  with depth-derived names (`UILabMenu1`, ...); `UIMenuStatsLabel` mirrors
  `isMenuMode`, top menu, stack depth, and `isWorldSimPaused` at 2 Hz.
- Localized-strings readout (`UIStringsStatsLabel`): synthetic sample key count
  plus merged translation file/key counts over the located install (loaded
  lazily, once).

`UIScene.localizedSample` (`opensky/UI/UILocalizedSample.swift`) is the
localized preview content: invented `$KEY` fixtures merged through the real
`TranslationFile` -> `LocalizedLabels` path, rendered via `label(for:)` — a
wrapped long paragraph (`maxWidth` 312 pt), an unwrapped line that clips past
the frame edge, and the deliberately unknown `$OPENSKY_UILAB_MISSING` token
shown verbatim ([UI translation strings](/formats/translation-strings.md)).

## Verification

- Device-free: layout/anchor/stack math, pixel snapping at 1.0/1.5/2.0, measurement
  monotonicity, wrap, draw-list quads/uv/white-texel, budget drops, resolve
  determinism (`UILayoutTests`); localized-sample resolution, verbatim
  unknown-key fallback, wrap/clip cases, per-scale resolve determinism
  (`UILocalizedSampleTests`); panel geometry, control round trips, readouts, and
  the pinned accessibility-id contract (`UILabPanelTests`); menu preview and
  strings snapshot state on the real controller (`GameViewControllerUILabTests`).
- Offscreen Metal-gated (`RendererUITests`, 480x320): labSample vs empty 64,567
  changed px; scale 1.0 vs 2.0 93,036 changed px; `uiEnabled=false` byte-identical
  to empty baseline; repeated render byte-identical.
- M8.1.4 acceptance (`RendererUIFoundationAcceptanceTests`, 480x320): localized
  sample vs empty 88,534 changed px; scale 1.0 vs 2.0 82,710 changed px; with
  `worldSimPaused` repeated frames byte-identical while `animationTime` holds
  at 0 and the overlay still draws.
- SWF layer (`RendererSWFTests`, 480x320, synthetic in-code movies): two placed
  rectangles change more than 2,000 px over the no-movie baseline;
  `swfEnabled = false`
  and clearing the movie both reproduce that baseline byte for byte; repeated
  frames byte-identical; a clip layer cuts the changed area to under a quarter
  of the unclipped draw with exactly 2 mask draws; draw stats count 2 draws /
  4 triangles for the two rectangles and 2 glyphs for an edit text over a
  synthetic font.
- Vanilla evidence is CLI-side (`openskycli swf render-sweep`, gates in
  `tools/probe.sh`): 53 of 53 movies render frame 1 with 0 failures. Numbers and
  the blank-frame explanation live in [SWF container](/formats/swf.md); captures
  stay under `logs/` because they embed game art.

## Limits / next

- System font plus SWF-font glyphs (M8.2.3) share the coverage-only atlas (no
  color glyphs/emoji), no clipping/scissor yet. Menu mode (the input-capture
  switch plus world-sim pause) landed in M8.1.2
  ([menu mode](/engine/menu-mode.md)) with the UI Lab preview as its trigger
  (M8.1.4); focus/text entry arrive with the SWF menu layer (M8.2).
- Atlas is fixed-size shelf pack; full-atlas behavior = glyph dropped from list
  (counted), never a crash.
