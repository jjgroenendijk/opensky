---
type: Subsystem
title: Screen-space UI layer
description: 2D overlay pass over the finished 3D frame - anchored value-type scene,
  layout + text primitives, CoreText system-font glyph atlas, points -> pixels scale
  handling, single premultiplied draw call, plus the SWF display-list render layer.
tags: [rendering, ui, metal, text, layout]
timestamp: 2026-07-26T00:00:00Z
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
- Eviction (issue #127): the atlas is one fixed-size texture shared by every movie,
  so a host that swaps movies must hand cells back or the shelf runs out and later
  movies render with no text. Each packed cell keeps the coverage bytes it was
  rasterized from (`UIGlyphAtlas.PackedGlyph`), and
  `releaseSWFGlyphs(where:)` (`UI/UIGlyphAtlasPacking.swift`) drops every `.swf`
  glyph whose `fontKey` matches the predicate, then repacks the survivors from
  their retained coverage — tallest cell first, ties broken by a total order over
  the key, so the repacked image is deterministic. System-font glyphs are never
  released (the dev UI outlives any movie). Survivors keep their metrics but move,
  so callers must re-query per frame; the bumped `revision` re-uploads the texture.
  `Renderer.setSWFMovie` calls it for the outgoing package's generation
  (`SWFTextPlanner.generation(forFontKey:)` reads the generation back out of the
  key). Counters for readouts: `packedGlyphCount`, `occupancy`, `packFailures`
  (glyphs dropped because the atlas was full, reset by an eviction).
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
  from `UIFrameUniforms.viewportSize`; fragment output is premultiplied —
`alpha = color.a * atlas.r`, `rgb = color.rgb * alpha` — matching the source-one blend.
- Shared structs/indices in `ShaderTypes.h`: `UIVertex` (pos/uv/color),
  `UIFrameUniforms`; `BufferIndexUIVertices/UIUniforms`, `TextureIndexUIAtlas`,
  `SamplerIndexUIAtlas`; argument-table counts bumped in `makeArgumentTable`.
- Renderer API: `uiEnabled` (default true), `uiScene` (default `.empty` -> zero
  draws), `uiScale` (default 1), `lastUIDrawStats` (`drawCalls, quads, glyphs,
  dropped, atlasWidth, atlasHeight, atlasGlyphs, atlasOccupancy,
  atlasPackFailures`). The atlas counters cover both text sources: the SWF layer
  packs into the same atlas and encodes before the overlay.

## SWF display-list layer (M8.2.4)

The SWF layer draws a movie's frame-1 display list over the finished 3D frame,
encoded inside the same scene pass immediately before the dev UI overlay (so
stats and readouts stay on top). Tag decode and the frame-1 semantics live in
[SWF container](/formats/swf.md); this section is the GPU side.

- Movie package (`Rendering/RendererSWFMovie.swift`, `SWFMovieResources`): built
  once per assigned movie. Every dictionary shape is tessellated through
  `SWFShapeCache` into one static twip-space vertex buffer with a per-fill run
  table (`RendererSWFBuild.swift`); bitmap characters upload as `rgba8Unorm`
  textures (carrying the decoder's `premultipliedAlpha` flag); gradient fills
  bake into a ramp atlas, one 256-texel row per fill; text draws are laid out in
  twips (`RendererSWFTextPlan.swift`, `SWFTextLayout`), viewport-independent.
  Per-draw uniform and glyph-vertex rings are triple-buffered and sized for the
  current command stream plus headroom (half again, floor 64), because a
  display list that ActionScript mutates outgrows an exact fit immediately.
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
  The renderer's 0.5...2 presentation multiplier scales that fit around the
  same viewport center rather than pinning the movie to an edge.
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
- Known visual gaps: line styles are not stroked (fills only), focal radial
  gradients render as plain radial, `linearRGB` gradient interpolation is
  treated as normal RGB, PlaceObject3 filters and blend modes are ignored, and
  glyph quads follow a transform's position and scale but not its rotation or
  skew (vanilla UI text is unrotated).

## Dynamic SWF path (M8.3.2)

The layer draws frame 1 until something runs the movie's ActionScript. The
[AS2 runtime](/engine/as2-runtime.md) owns the mutable display list and produces
the same `SWFScene` command stream the static flattener does, so the encode path
is unchanged; only the source of the stream differs.

- Renderer API (`Rendering/RendererSWFRuntimePass.swift`), all main thread,
  between frames:

  ```swift
  var swfRuntime: SWFMovieRuntime? { get }
  @discardableResult
  func startSWFRuntime(limits: AS2Limits = .standard) throws -> SWFMovieRuntime?
  func advanceSWFRuntime() throws
  @discardableResult
  func sendSWFInput(_ event: SWFInputEvent) throws -> Bool
  @discardableResult
  func callSWFMovie(_ name: String, arguments: [AS2Value] = []) throws -> AS2Value
  @discardableResult
  func callSWFMovie(
      _ name: String, atPath path: String, arguments: [AS2Value] = []
  ) throws -> AS2Value
  func updateSWFRuntime(_ body: (SWFMovieRuntime) -> Void) throws
  func stopSWFRuntime() throws
  func updateSWFScene(_ scene: SWFScene) throws
  ```

  `startSWFRuntime` brings the assigned movie up (every `DoInitAction`, then
  frame 1, then its `DoAction`) and pushes the display list it produced.
  `advanceSWFRuntime` ticks it once and pushes a new stream **only** when the
  tick changed something. `sendSWFInput` injects one pointer or key event and
  pushes whatever the movie changed in response, answering whether the movie
  consumed it; `callSWFMovie` is the engine-to-movie half of the
  [`GameDelegate` bridge](/engine/as2-runtime.md) and pushes the same way.
  Its path overload reaches functions on a named display object.
  `updateSWFRuntime` batches several engine-owned mutations and synchronizes
  one command stream afterwards; a failed GPU update restores the runtime's
  dirty flag so the same state can be retried.
  `stopSWFRuntime` drops the runtime and restores the static frame-1 stream.
  `setSWFMovie` clears any runtime, because a new movie invalidates the old
  one's tree.
- Cheap update (`SWFMovieResources.update(scene:device:)`): re-plans draw ops,
  uniforms, and text runs from a new command stream while **retaining** every
  static GPU resource — tessellated geometry, bitmap textures, the gradient
  ramp, and the shared glyph atlas. The text planner is kept alive across
  updates so external-font atlas keys stay stable; re-keying them per update
  would refill the atlas with duplicates. Rings grow (never shrink) when a
  stream outgrows them, and the replaced buffers retire once in-flight frames
  drain, exactly like a movie swap. Draws past the ring capacity are still
  counted in `skippedItems` rather than dropped silently.
- Per-instance text reaches the renderer on `SWFSceneItem.textOverride`, an
  additive field that is nil on the static path, and re-lays out through
  `SWFTextLayout.editText(_:font:content:)`.
- **Determinism**: the encode path is still a pure function of the command
  stream plus the viewport, and nothing in the layer reads a wall clock or a
  frame counter. The layer moves only when the engine calls
  `advanceSWFRuntime()`, so a movie that is not advanced renders byte-identically
  frame to frame — the static contract, restated as an explicit-tick contract
  rather than weakened. Input is injected rather than read, so the same event
  sequence always produces the same frame; `setInterval` callbacks fire from the
  tick rather than from a clock; and `Math.random` inside a movie draws from a
  seeded generator for the same reason.
- Driven from the app since M8.3.3: the **SWF runtime** section under
  `Developer > UI Lab` starts, ticks, drives, and stops a runtime (see
  App surface below). A movie nobody starts still shows frame 1 only.

## Vanilla gameplay HUD (M8.4.2)

The app now loads `Interface\hudmenu.swf` through the same VFS-backed
`SWFMovieLoader` used by UI Lab, starts its AS2 runtime, and validates the
functions on `/HUDMovieBaseInstance` before publishing any state. Missing game
data, a missing entry point, or a renderer failure leaves the HUD disabled and
logs the reason; it does not prevent the 3D world from starting.

`HUDMovieBridge` owns the typed engine-to-movie contract:

- `SetCrosshairEnabled` keeps the vanilla crosshair visible.
- `SetHealthMeterPercent`, `SetMagickaMeterPercent`, and
  `SetStaminaMeterPercent` receive clamped 0...1 values. M8.4.2 initializes all
  three to full; live actor statistics are later scope.
- `SetCrosshairTarget` receives the current interaction prompt, such as
  `Open <door name>`, or an empty hidden target when nothing is selected.
- `CompassTargetDataA` receives a flat four-value record per marker: heading,
  Flash `_alpha`, the movie's own marker-type value, and Flash scale.
  `SetCompassMarkers` applies that array. M8.4.2 publishes one location marker
  for the selected interaction target.
- `SetCompassAngle` receives the camera heading and keeps the compass visible.

Those names and argument shapes were observed by probing the legally owned
installed movie: the HUD starts with 203 display nodes and no runtime faults,
and the meter setters retained a supplied `0.75` percent value. The marker
array field order was observed in the movie's own `CompassTargetDataA`
consumer; alpha and scale use Flash's 0...100 property units. A 1280x720
offscreen run over that movie changed 1,783 pixels after publishing a prompt
and marker, with 208 draw calls, zero skipped items, and zero runtime faults;
its local statistics remain under gitignored `logs/`.

OpenSky maps world +X to zero degrees, normalizes into 0..<360, and passes the
same camera yaw as the player and compass angles. The public SWF format does not
specify this HUD-specific GFx contract. M8.4.3's local visual check confirmed
that heading zero centers the movie's north marker and that publishing a prompt
does not move the compass.

HUD state changes are collected by `GameViewControllerHUD` and applied once
between frames. Target callbacks only mark prompt and marker state dirty; the
frame hook owns renderer mutation. This static milestone deliberately does not
advance the movie timeline at the display refresh rate: direct HUD methods
update the required state, and tying one AS2 tick to each 60 or 120 Hz display
frame would make behavior depend on the monitor. Timed HUD animation needs an
explicit movie-frame cadence in later scope.

The gameplay HUD owns the single SWF layer by default. Choosing a movie in
`Developer > UI Lab > SWF movie` is an explicit debug override; choosing
`None` restores `hudmenu.swf`.

## HUD acceptance surface (M8.4.3)

`World > HUD & Interaction` is a separate World destination because the
milestone names that exact path. Its two sections talk through
`HUDControlProviding`; the panel does not own renderer or targeting state.

- **Elements** A/Bs the live layer, crosshair, actor meters, compass,
  interaction marker, activation prompt, and the movie's authored placeholder
  text. Scale presets are 50, 75, 100, 125, 150, and 200 percent. The readout
  reports load/error state, effective scale, draw calls, and skipped items.
  Gameplay elements default on, authored placeholder text defaults off, and
  the section participates in destination and Reset-all override provenance.
- **Target** reports the current walk-mode REFR and base FormIDs, action and
  resolved name, distance, placed and hit positions, exact prompt, camera
  heading, and marker headings. It has no synthetic preview: the acceptance
  surface must expose a broken live targeting or localization path rather than
  masking it.

Element toggles mutate the existing runtime between frames. Crosshair and
compass visibility use the movie's observed setters. Meter visibility changes
the installed `/HUDMovieBaseInstance/Health`, `Magica`, and `Stamina` clips,
whose paths were observed in the legally owned movie's runtime tree. The
installed movie also starts with authoring samples visible under
`/HUDMovieBaseInstance/RolloverInfoInstance` and
`/HUDMovieBaseInstance/SubtitleTextHolder`. Initialization hides both so raw
font markup and `Dialogue Line 1Dialogue Line 2` do not leak into gameplay;
**Authored placeholder text** makes them intentionally inspectable. Scale is a
centered renderer presentation multiplier and does not mutate the display
list. UI Lab still owns an explicit whole-movie override; selecting `None`
restores the HUD with its saved M8.4.3 element and scale preferences.

The environment-gated `HUDAcceptanceRealDataTests` builds the installed
walk-route farm cell, exact-raycasts real door REFR `0001633D` at 83.329315
units, and feeds its `Open Door` prompt to the installed `hudmenu.swf`. At
1280x720, prompt off/on changed 4,069 pixels with zero skipped items. Both
frames and the report stay in gitignored `logs/`. Local inspection confirmed
the activation text appears at the crosshair and the compass/crosshair remain
stable; no game-art capture is tracked.

## App surface

`Developer > UI Lab` sidebar destination — the M8.1 foundation acceptance surface
(M8.1.4), the M8.2 SWF static-render acceptance surface (M8.2.5), and the M8.3.3
AS2 runtime acceptance surface, talking to the engine through
`UILabControlProviding` and `SWFLabControlProviding` on `GameViewController`
(bridges split to `opensky/GameViewControllerUILab.swift`,
`opensky/GameViewControllerSWFLab.swift`, and
`opensky/GameViewControllerSWFRuntime.swift` for the file-size limit;
weak-provider pattern shared with the Environment panel):

- Overlay enable (`UIOverlayEnabledControl`), lab-sample toggle
  (`UILabSampleControl`), localized-sample toggle (`UIStringsSampleControl` —
  the two samples share `Renderer.uiScene`, so enabling one clears the other),
  scale presets 50/100/150/200% (`UIScaleControl`), live draw-stats readout
  (`UIStatsLabel`) — draw calls, quads, glyphs, dropped, plus atlas size, packed
  glyph count, occupancy, and atlas overflow. The atlas lines are how a user
  watches eviction work: swap movies in the **SWF movie** section below and the
  packed-glyph count returns to the new movie's own demand instead of climbing.
- Menu-mode preview: Push menu / Pop / Clear buttons (`UIMenuPushControl`,
  `UIMenuPopControl`, `UIMenuClearControl`) drive the real `MenuModeController`
  with depth-derived names (`UILabMenu1`, ...); `UIMenuStatsLabel` mirrors
  `isMenuMode`, top menu, stack depth, and `isWorldSimPaused` at 2 Hz.
- Localized-strings readout (`UIStringsStatsLabel`): synthetic sample key count
  plus merged translation file/key counts over the located install (loaded
  lazily, once).
- SWF movie selector (M8.2.5), a hosted child section titled **SWF movie**
  (`PanelSection-swfMovie`): a popup listing `None` plus every
  `Interface\*.swf` in the located install (`SWFMovieControl`), a layer toggle
  bound to `Renderer.swfEnabled` (`SWFLayerEnabledControl`), and a readout
  (`SWFMovieStatsLabel`) that shows the selected movie, the decoded
  `SWFMovieTally` (place/move/remove counts, `ShowFrame`s, sprites, clip
  layers, filters, blend modes, `ClipActions`, dangling placements), the
  whole-movie ActionScript inventory added in M8.3.1 (`Actions:` — action
  blocks, ACTIONRECORDs, unknown opcodes, undecoded opcodes, parse warnings;
  nothing executes yet), the live `SWFDrawStats`, unresolved font names, and any
  load error. Selecting an entry
  runs `SWFMovieLoader.load(path:)` -> `Renderer.setSWFMovie(_:)`; `None`
  restores the gameplay HUD when the renderer is available (and otherwise
  clears the layer). Bridge:
  `SWFLabControlProviding` on `GameViewController`
  (`opensky/GameViewControllerSWFLab.swift`), readout text built by the
  device-free `SWFLabReadout`. The loader and the movie list resolve once,
  lazily, because enumerating movies walks every archive index and the 2 Hz
  ticker must not repeat it. No install, an undecodable movie, or a failing GPU
  package build all degrade to an explanatory readout — never a throw out of a
  control action.
- **SWF runtime driver (M8.3.3)**, a second hosted child section titled
  **SWF runtime** (`PanelSection-swfRuntime`,
  `opensky/Shell/Sections/SWFRuntimeSection.swift` plus its
  `SWFRuntimeSectionInput.swift` action satellite). It runs the movie the
  selector above assigned, so the two sections are ordered selector then
  runtime. Controls, all disabled until they can do something — Start needs an
  assigned movie, everything else needs a running runtime:
  - Transport: `SWFRuntimeStartControl` (`Renderer.startSWFRuntime()`),
    `SWFRuntimeTickControl` (one `advanceSWFRuntime()`),
    `SWFRuntimeTickBurstControl` (twenty, because a vanilla menu's open and
    close animations are each about twenty frames), `SWFRuntimeStopControl`
    (`stopSWFRuntime()`, back to the static frame-1 stream).
  - Input: a navigation-key popup (`SWFRuntimeKeyControl` — Left, Up, Right,
    Down, Enter, Escape, Space, Tab, from `SWFKeyCode`) plus
    `SWFRuntimeSendKeyControl`, which injects the key down and its up.
    `SWFRuntimePointerXControl` / `SWFRuntimePointerYControl` take a position
    in **movie stage pixels** for `SWFRuntimePointerMoveControl` (one
    `pointerMoved`) and `SWFRuntimePointerClickControl` (`pointerPressed` then
    `pointerReleased` at the same point).
  - Bridge: an editable combo box (`SWFRuntimeCallControl`) prefilled with the
    movie's own `GameDelegate.addCallBack` names, plus
    `SWFRuntimeCallInvokeControl` (`Renderer.callSWFMovie(_:)`, no arguments)
    and `SWFRuntimeClearLogControl`. Editable rather than a fixed popup because
    a menu's entry points are not all enumerable: `tweenmenu.swf` registers
    `StartOpenMenuAnim` and `StartCloseMenuAnim` with the delegate, but
    `SetPlatform` and `InitExtensions` are plain root-clip functions that
    `callMovie` reaches through its fallback.
  - Readouts, the three the M8.3.3 gate names, all built by the device-free
    `SWFLabReadout` from a `SWFLabRuntimeSnapshot`
    (`opensky/SWFLabRuntimeReadout.swift`) at 2 Hz:
    `SWFRuntimeStatsLabel` (started/loaded, tick count, root playhead and frame
    count, node count, root child count, focus target path, pointer/key event
    counts, last key code, live timers, and dropped instantiations / frame
    actions / timers), `SWFRuntimeInvokeStatsLabel` (invoke totals, unhandled
    count, dropped count, the movie's registered callback names, and the last
    six entries as `direction name(args) -> result` with `[unhandled]` marked),
    and `SWFRuntimeTallyStatsLabel` (actions/blocks/calls executed, fault total
    with ranked kinds, stack underflows, ranked unimplemented opcodes, ranked
    missing host-API names, and the last `trace` message). Every clipped list
    keeps its total beside it, so a truncated readout never reads as complete.
  - Bridge implementation: `opensky/GameViewControllerSWFRuntime.swift`. Like
    the selector, no control action throws — a start with no movie, a tick
    before Start, a blank callback name, a missing Metal 4 device, and a GPU
    failure inside a push all land in the same `loadError` the selector's
    readout shows.

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
- M8.2.5 static-render acceptance (`RendererSWFStaticAcceptanceTests`, 480x320,
  one synthetic menu-shaped movie: plate + nested sprite + clip layer + edit
  text over a synthetic font): 6 draws, 18 triangles, 4 glyphs, 2 mask draws, 0
  skipped, 103,686 changed px over the movie-free baseline. The same movie with
  an alpha-zero CXFORM on every top-level placement still encodes its 6 draws
  and reproduces the baseline **byte for byte** — the pinned reproduction of why
  most vanilla menus render blank at frame 1. `swfEnabled = false`, clearing the
  movie, and re-assigning it all behave: baseline byte-identical when off or
  cleared, identical frames and identical stats when reassigned, repeated frames
  byte-identical.
- M8.3.2 dynamic-render acceptance (`RendererSWFDynamicAcceptanceTests`,
  480x320, one synthetic movie whose whole frame-1 content sits under an
  alpha-zero CXFORM and whose frame-1 `DoAction` sets `panel._alpha = 100`):
  frame 1 encodes 2 draws and changes **0** pixels over the movie-free baseline;
  after `startSWFRuntime()` the same movie changes **68,160** pixels with 0
  skipped items and 0 AS2 faults. The same movie with its `DoAction` removed
  stays at 0 changed pixels after bring-up, which is what makes the delta
  attributable to the ActionScript rather than to the runtime existing.
  Determinism: with the runtime started but never advanced, repeated frames are
  byte-identical, and advancing a one-frame movie keeps them byte-identical.
  Ring growth: a movie whose second frame places 200 more rectangles encodes 1
  draw before the tick and 201 after, with 0 skipped. `stopSWFRuntime()`
  reproduces the static frame byte for byte.
- M8.3.3 interactive acceptance (`RendererSWFInteractiveAcceptanceTests`,
  480x320, one synthetic movie whose `highlight` clip is hidden by an alpha-zero
  CXFORM and whose `button` clip carries the handlers that reveal it): a pointer
  move onto the button is consumed and changes **59,840** pixels; a pointer move
  onto empty stage is not consumed and changes **0**; a key down routed to the
  menu's own `handleInput` changes the same 59,840. Determinism holds across
  input: frames between injected events are byte-identical, and re-injecting the
  same pointer position sends no second rollover and changes nothing. An
  engine-to-movie call the movie never registered leaves the frame untouched and
  lands in the invoke log as unhandled.
- Vanilla evidence is CLI-side (`openskycli swf render-sweep`, gates in
  `tools/probe.sh`): 53 of 53 movies render frame 1 with 0 failures. Per-movie
  changed-pixel counts, tag tallies, and the blank-frame explanation live in
  [SWF container](/formats/swf.md); captures stay under `logs/` because they
  embed game art.
- M8.3.3 panel coverage, device-free and install-free: the runtime snapshot and
  the three readouts, including every truncation case
  (`SWFLabRuntimeReadoutTests` — the snapshot is also asserted against a live
  `SWFMovieRuntime` built from a synthetic movie); the section's control
  wiring, gating, callback list, and pinned accessibility ids
  (`SWFRuntimeSectionTests`); the bridge reporting instead of throwing without
  a renderer (`GameViewControllerSWFLabTests`); hosting inside the UI Lab
  document (`UILabPanelTests`).
- M8.4.3 panel coverage, device-free and install-free:
  `HUDInteractionPanelTests` pins both section identifiers, every control id,
  provider round trips, default reset, the live target readout, refocus, and
  panel geometry. `DestinationRegistryTests` pins placement under World,
  game-view visibility, and unopened-destination override reset. The exact
  acceptance path is `World > HUD & Interaction`: use **Elements** to A/B the
  layer, crosshair, meters, compass, marker, prompt, and centered scale while
  **Target** shows the live walk-mode selection and movie payload.
- M8.2 milestone acceptance sidebar path: `Developer > UI Lab > SWF movie` —
  pick `console.swf`, `creationclubmenu.swf`, `quest_journal.swf`,
  `bookmenu.swf`, or `hudmenu.swf` from `SWFMovieControl`, watch
  `SWFMovieStatsLabel`, and A/B the frame with `SWFLayerEnabledControl`.
- M8.3 milestone acceptance sidebar path:
  `Developer > UI Lab > SWF movie` then `Developer > UI Lab > SWF runtime`.
  Open / navigate / close on `tweenmenu.swf`, click by click:
  1. `SWFMovieControl` -> `tweenmenu.swf` (assigns the movie; frame 1 is blank,
     which is correct).
  2. `SWFRuntimeStartControl` — Start. The state readout goes to
     `Runtime: running`, and the tally shows the bring-up ops.
  3. `SWFRuntimeCallControl` -> type `SetPlatform`, then
     `SWFRuntimeCallInvokeControl`. Repeat for `InitExtensions`. Both are
     root-clip functions, so they are typed rather than picked.
  4. `SWFRuntimeCallControl` -> pick `StartOpenMenuAnim` from the list, then
     Call. Press `SWFRuntimeTickBurstControl` once (twenty ticks) — the invoke
     readout gains `movie->engine OpenAnimFinished()`.
  5. Navigate: `SWFRuntimeKeyControl` -> `Down`/`Up`/`Left`/`Right`, then
     `SWFRuntimeSendKeyControl` for each. Every accepted move fires
     `movie->engine HighlightMenu(n)` into the invoke readout. Hovering works
     the same way through `SWFRuntimePointerXControl`/`Y` +
     `SWFRuntimePointerMoveControl`.
  6. Close: `SWFRuntimeCallControl` -> `StartCloseMenuAnim`, Call, then
     `SWFRuntimeTickBurstControl` — `movie->engine CloseMenu()` lands in the
     log. `SWFRuntimeStopControl` returns the layer to the static frame.

  Measured on the user's own install through exactly those controls (output to
  `logs/`, never committed — a rendered vanilla menu embeds game art): 39 nodes
  at bring-up rising to 84, invoke log 10 entries with 1 unhandled
  (`OpenHighlightedMenu`, which no host function was registered for), 76,572
  actions / 79 blocks / 2,491 calls, **0 faults**, 0 unimplemented opcodes, and
  26 missing host-API hits headed by `getControllerFocusGroup`.

## Limits / next

- System font plus SWF-font glyphs (M8.2.3) share the coverage-only atlas (no
  color glyphs/emoji), no clipping/scissor yet. Menu mode (the input-capture
  switch plus world-sim pause) landed in M8.1.2
  ([menu mode](/engine/menu-mode.md)) with the UI Lab preview as its trigger
  (M8.1.4); focus/text entry arrive with the SWF menu layer (M8.2).
- Atlas is fixed-size shelf pack; full-atlas behavior = glyph dropped from list
  (counted in `packFailures` and in the SWF layer's `skippedItems`), never a crash.
  Releasing a movie reclaims its cells (above), so a movie-swapping host no longer
  exhausts it, but a single movie needing more than 512x512 of coverage still
  drops glyphs. Growing the atlas is the next step if one appears.
