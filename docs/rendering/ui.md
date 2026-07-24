---
type: Subsystem
title: Screen-space UI layer
description: 2D overlay pass over the finished 3D frame - anchored value-type scene,
  layout + text primitives, CoreText system-font glyph atlas, points -> pixels scale
  handling, single premultiplied draw call.
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
  render that places these glyph quads is 8.2.4.
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

## Limits / next

- System font plus SWF-font glyphs (M8.2.3) share the coverage-only atlas (no
  color glyphs/emoji), no clipping/scissor yet. Menu mode (the input-capture
  switch plus world-sim pause) landed in M8.1.2
  ([menu mode](/engine/menu-mode.md)) with the UI Lab preview as its trigger
  (M8.1.4); focus/text entry arrive with the SWF menu layer (M8.2).
- Atlas is fixed-size shelf pack; full-atlas behavior = glyph dropped from list
  (counted), never a crash.
