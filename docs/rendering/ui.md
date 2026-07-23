---
type: Subsystem
title: Screen-space UI layer
description: 2D overlay pass over the finished 3D frame - anchored value-type scene,
  layout + text primitives, CoreText system-font glyph atlas, points -> pixels scale
  handling, single premultiplied draw call.
tags: [rendering, ui, metal, text, layout]
timestamp: 2026-07-22T00:00:00Z
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

`World > UI Lab` sidebar destination: overlay enable, sample-overlay toggle, scale
presets (50/100/150/200%), live draw-stats readout via `UILabControlProviding` on
`GameViewController` (weak-provider pattern shared with the Environment panel).
Extends at M8.1.4 into the full UI Lab acceptance surface.

## Verification

- Device-free: layout/anchor/stack math, pixel snapping at 1.0/1.5/2.0, measurement
  monotonicity, wrap, draw-list quads/uv/white-texel, budget drops, resolve
  determinism (`UILayoutTests`).
- Offscreen Metal-gated (`RendererUITests`, 480x320): labSample vs empty 64,567
  changed px; scale 1.0 vs 2.0 93,036 changed px; `uiEnabled=false` byte-identical
  to empty baseline; repeated render byte-identical.

## Limits / next

- One font family (system), coverage-only atlas (no color glyphs/emoji), no
  clipping/scissor. Menu mode (input-capture switch + world-sim pause) landed in
  M8.1.2 ([menu mode](/engine/menu-mode.md)); focus/text entry arrive with the SWF
  menu layer, localized strings M8.1.3.
- Atlas is fixed-size shelf pack; full-atlas behavior = glyph dropped from list
  (counted), never a crash.
