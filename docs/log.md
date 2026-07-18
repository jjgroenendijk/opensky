# Change log

Newest first. ISO-8601 date headings. See AGENTS.md "Documentation wiki".

## 2026-07-18

* **Cell streaming grid manager** (M3.2, grid-manager sub-item): new
  `opensky/World/CellGridManager.swift` -- pure `simd`-only value type, camera
  `SIMD3<Float>` position -> desired NxN exterior-cell grid (`uGridsToLoad`
  default 5 -> radius 2, ref UESP "Skyrim:INI Settings" Grid section), diffed
  against a caller-supplied loaded set. Floor-division cell mapping (not
  truncation -- negative coords land correctly). Ownership split: the manager
  tracks only its desired center cell; the loaded set stays with the caller
  so async loads (later commit, same 3.2 item) can finish out of order or
  fail without the manager drifting from reality -- `update` always diffs
  fresh against whatever `loaded` the caller reports that frame. Hysteresis
  (128-unit margin, checked per axis) stops a camera oscillating across a
  cell border from thrashing load/unload. Docs:
  [cell-streaming](/engine/cell-streaming.md). Tests: `CellGridManagerTests`
  -- floor mapping incl. negative/boundary coords, 5x5 grid contents, radius
  parameter, one-cell-move diff (leading/trailing edge), hysteresis no-thrash,
  decisive-crossing, diagonal-corner cases.
* **Frustum culling math** (M3.2, math only): new `Rendering/Frustum.swift` —
  `Frustum(viewProjection:)` extracts 6 inward planes from a `P * V` matrix
  (Gribb/Hartmann 2001, adapted to column-vector convention + Metal's z in
  [0, 1] clip range: near = row2 alone, not row3 + row2), plus a conservative
  positive-vertex `intersects(min:max:)` AABB test and a `ModelBounds`
  convenience overload. Pure, renderer-independent — `Renderer.swift`/
  `RenderScene.swift` wiring lands with rest of 3.2 cell streaming so world
  AABBs are available per loaded cell. Docs:
  [metal4-renderer](/rendering/metal4-renderer.md) Frustum culling section.
  Tests: `FrustumTests` (ahead/behind/left/right/above/below, near-plane
  straddle kept, beyond-far culled, enclosing box kept, degenerate point).
* **Agent workflow efficiency — skills split + dev-loop make targets**: transcript
  mining of 35 sessions (3.7k shell commands) drove two changes. (1) Makefile gains
  the observed repeated loops as targets: `fix` (format then strict lint, one shot),
  `test-one T=Class[/test]` (replaces hand-typed `xcodebuild -only-testing`
  invocations), `test-report` (newest `.xcresult` summary via `xcresulttool`),
  `app-path`/`cli-path` (built-product paths via `-showBuildSettings`, replaces
  DerivedData globbing), `run-cli ARGS=...` (build + exec `openskycli`). (2) Root
  AGENTS.md slimmed to always-relevant rules (295 -> 197 lines); conditional
  workflows moved to skills under `.AGENTS/skills/`: new `format-parser`
  (reverse-engineering discipline), `docs-wiki` (OKF rules), `probe` (env-gated
  real-data scratch-test template modeled on `CellRenderRealDataTests`, MainActor
  rules, offscreen render verification paths) joining existing `commit`.
  `docs/todo.md` handoff section cut to pointers; stale PR-state snapshot removed
  (live state comes from `gh pr list`). `openskypreview` gains a real
  main menu (Settings… Cmd+, / Edit / Quit) and a Settings window that shows
  the resolved game data root + source and lets the user pick the install
  folder via `NSOpenPanel` — validated + persisted through new
  `GameDataLocator.saveUserChoice`/`clearUserChoice`; browser catalog reloads
  live on change (new `PreviewViewController.reload`, catalog-load generation
  counter drops stale loads). Data-root setting now lives in shared defaults
  domain `nl.jjgroenendijk.opensky` (`GameDataLocator.settingsDefaults`) so
  app/preview/CLI read one setting despite differing bundle ids. Docs:
  [preview-gui](/tools/preview-gui.md), [locator](/engine/game-data-locator.md).
  Tests: `GameDataLocatorTests` save/clear cases.
* **Terrain 3x3 grid verify, closes M3.1** (M3.1): `openskycli render --neighbors` builds
  the target cell plus its 8 grid neighbors off one shared `MeshLibrary`/`TextureLibrary`/
  `CellSceneBuilder` (residency + STAT index dedup across cells, not a streaming grid
  manager — that's 3.2) and composes the 9 `CellScene`s with new `RenderScene(merging:)`
  (`opensky/Rendering/RenderScene.swift`: flat concat of the opaque/alpha-tested/terrain
  draw lists — items already carry absolute world matrices, no re-transform). Camera
  generalizes `SceneCamera.framing` to the union of all 9 bounds. A neighbor slot that
  fails to build (void grid position, malformed worldspace) warns to stderr and is
  skipped, not fatal. Real-install run over Tamriel (6,-2) + 8 neighbors (Whiterun): all 9
  slots built (WhiterunExterior02/03/05/06/08/09/10, ChillfurrowFarmExterior, cell
  000095F9), 0 missing textures, 4 terrain quads/cell; visually verified (default + a
  temporary steep top-down angle, not committed) — terrain continuous under the M2 walls
  across all 9 cells, no height cracks or gaps at any internal cell border, splat
  variation visible city-wide. Screenshot:
  [terrain-3x3-whiterun.png](/img/terrain-3x3-whiterun.png). Docs:
  [terrain](/engine/terrain.md) Verification section, [cli](/tools/cli.md) `--neighbors`.
  Tests: `RenderSceneTests` merge cases (concat counts, cross-scene residency dedup, empty
  input). Closes milestone 3.1 (`docs/todo.md`).
* **Terrain splat pipeline** (M3.1): third render pipeline (`TerrainSplat`,
  `terrainVertex`/`terrainFragment`) blends each quadrant's BTXT base with up
  to 8 ATXT layer diffuses by per-vertex VTXT opacities in one draw. Binding
  decision: per-quadrant multi-texture argument-table binds (base at
  `TextureIndexDiffuse`, `array<texture2d, 8>` at `TextureIndexTerrainLayer0`;
  `texture2d_array` rejected — layer diffuses vary in size/format; per-layer
  draws rejected — blend pipeline + N draws/quadrant). Weights = second vertex
  stream (`BufferIndexTerrainWeights`, two float4 lanes) — static 48-byte
  layout untouched. `TerrainMeshBuilder` now emits `Patch` values (mesh + base
  FormID + layers, VTXT baked dense: position 0-288 = 17x17 row-major, UESP
  LAND); `CellSceneBuilder` resolves base + layer LTEX->TXST diffuses, drops
  broken layer chains (counted, `terrainLayerSkipCount`), packs weights, emits
  `RenderScene.terrain` items. Blend = ordered `mix(albedo, layer, opacity)`;
  exact vanilla curve UNCONFIRMED. Cap `TerrainConstantMaxLayers = 8` (format
  max; vanilla ~6/quadrant). Lighting identical to static path; TX01 normal
  maps deferred. Docs: [metal4-renderer](/rendering/metal4-renderer.md) splat
  section + [terrain](/engine/terrain.md) rewrite. Tests: weight bake/pack +
  layer routing (`TerrainMeshBuilderTests`), resolution + blend order + drop
  accounting (`CellSceneTerrainTests`), GPU pixel-level blend proof
  (`TerrainSplatRenderTests`), terrain residency (`RenderSceneTests`). Visual:
  WhiterunExterior06 render — 4 quads, 14 layers, dirt/grass/rock/snow
  transitions under the M2 walls.
* **Terrain mesh build** (M3.1): new `opensky/World/TerrainMeshBuilder.swift`
  turns a decoded LAND into engine `Mesh`/`Model` values — 33x33 vertex grid,
  128-unit quads over the 4096 cell, heights passthrough (VHGT already *8),
  VNML normals (`v/127` normalized, zero/absent -> up), VCLR colors, UVs
  `(c,r)/2` (density UNCONFIRMED, tuned in splat commit). One sub-mesh per
  painted, non-hidden quadrant (XCLC quad-flags force-hide) with its BTXT base
  material resolved BTXT -> LTEX(TNAM) -> TXST(TX00) via `ESMWalk`, paths
  canonicalized through `NIFShaderTextureSet.vfsKey`. `CellSceneBuilder` places
  terrain at `(gridX*4096, gridY*4096)` (REFR world frame), appends opaque
  DrawItems under the objects, feeds `CellScene.bounds`, adds
  `terrainQuadrantCount` to the summary. LAND-less exterior cell -> flat plane
  at WRLD DNAM default land height (new `Worldspace.defaultLandHeight`/
  `defaultWaterHeight`; Tamriel -27000); DNAM absent -> no ground (UNCONFIRMED,
  probe later). Docs: [terrain subsystem](/engine/terrain.md), cell-scene LAND
  note updated. Synthetic-fixture tests (`TerrainMeshBuilderTests`,
  `CellSceneTerrainTests`). Edge-overlap probe (`LandRealDataTests`, real
  Tamriel): 4 adjacent pairs, 0 mismatched edge vertices — shared row/col match
  exactly, overlap claim confirmed (streaming can weld by dropping a shared edge).
  Splat render is the next 3.1 item.
* **LAND/LTEX/TXST decoders** (M3.1): new terrain record decoders in
  `opensky/Formats/ESM/Records/{Land,LandTexture,TextureSet}.swift` +
  [land format doc](/formats/land.md). LAND = VHGT gradient height field
  (float anchor + 33x33 int8 deltas; col 0 carries row-to-row, cols 1-32
  accumulate west->east, result *8 game units), VNML/VCLR 33x33x3 bytes,
  BTXT base + paired ATXT/VTXT splat layers (quadrant 0-3, VTXT position
  0-288, float opacity). LTEX TNAM -> TXST TX00 diffuse / TX01 normal. Ref
  UESP LAND/LTEX/TXST + xEdit `wbDefinitionsCommon.pas`. Synthetic-fixture
  unit tests (`TerrainRecordDecoderTests`) + env-gated Tamriel sweep
  (`LandRealDataTests`). Sweep over vanilla Skyrim.esm: 11186 LAND records
  decoded no throws, height -37032..39392 units, up to 23 cell-wide splat
  layers, VTXT position max 288, quadrants {0,1,2,3}. Decoders only; mesh
  build + splat render are later 3.1 items.
* **Milestone 3 detailed plan**: expanded [todo](/todo.md) M3 into sub-itemed
  3.1-3.7 (terrain -> streaming -> LOD -> sky/water -> interiors -> lighting
  -> gate) with per-item acceptance, spec refs, probe strategy, dependency
  order (3.4/3.5 parallelizable vs 3.2/3.3). Format facts pre-verified
  against open specs — UESP mod-file-format pages (LAND/CELL/WRLD/LTEX/TXST/
  REFR/DOOR/WATR/LGTM/LIGH/WTHR/CLMT, LOD Settings File Format), xEdit
  `dev-4.1.6` source (`wbDefinitionsTES5.pas`, `wbDefinitionsCommon.pas`,
  `wbLOD.pas`, `wbImplementation.pas`), DynDOLOD docs + xLODGen LODGen
  source. Key facts folded into item text: VHGT row-carry x8 height decode;
  .btr/.bto are NIF containers (BSMultiBoundNode / BSSubIndexTriShape),
  level N = NxN cells SW-anchored, 16-B lodsettings; XTEL 32-B dest-REFR
  teleport; interior block/sub-block = FormID last decimal digits; XCLW
  no-water sentinels; XCLL truncation variants. Flagged UNCONFIRMED for
  impl-time probes: LAND-less-cell flat-plane fallback, live per-quad layer
  limit (~6, community), XCLL rotation units, vanilla .btr/.bto blocks
  beyond what xLODGen emits.
* **Milestone 2 accepted** (2.11, complete — M2 left [todo](/todo.md)):
  target cell textured + recognizable, free-fly verified (2.7/2.8), fps
  gate measured not eyeballed via new `openskycli bench` — offscreen path
  split into `RendererOffscreen.swift`, every frame FrameStats-instrumented,
  `renderOffscreenSustained` returns per-frame wall times. Apple M1,
  Debug, real install, `WhiterunExterior06`, 360 frames: avg 0.39 ms
  (2557 fps) p95 0.43 ms @ 1280x720; avg 0.54 ms (1846 fps) @ 1920x1080 —
  far above the 30 fps bar. `bench` wired into `make probe`; `render`
  gained `--zoom` (framing camera alone leaves ~4% of pixels covered).
  Screenshot (engine output only) committed:
  [m2-whiterun-exterior.png](/img/m2-whiterun-exterior.png), referenced
  with numbers from [renderer doc](/rendering/metal4-renderer.md). M3
  items re-checked against M2 (notes in todo): ordering unchanged,
  `CellSceneBuilder` is the streaming unit, bench/preview are the M3
  verification path.
* **Agent rules restructure**: root AGENTS.md slimmed — tool-target rules
  moved next to the code (`openskycli/AGENTS.md`,
  `openskypreview/AGENTS.md`, each with `CLAUDE.md` symlink), commit/PR
  procedure moved to a skill (`.AGENTS/skills/commit/SKILL.md`,
  `.claude/skills` symlinks to it; `.claude/*` harness state now
  gitignored). Root keeps the global contract + non-negotiables.
* **Asset preview GUI** (2.10, complete): new `openskypreview` app target
  (same synchronized-group sharing as the CLI; `make preview` builds).
  Programmatic AppKit browser: category popup (meshes/textures/records/
  all) with filter and lazy table over `PreviewCatalog` (archive entries
  via `VirtualFileSystem.archiveEntries()` + headers-only `ESMWalk` over
  every Skyrim.esm record); catalog load + record filtering off-main. Detail
  pane: NIF -> single-model offscreen render via MeshLibrary + framing
  camera; DDS -> `TexturePreviewScene` textured quad with black sun +
  white ambient (fragment output = sampled texel); record ->
  `RecordTextDump` (shared impl — CLI `record` prints the same string;
  `ESMWalk` moved to `opensky/Formats/ESM/`). Missing install ->
  in-window message, app still launches. Unit tests: catalog grouping +
  filter, dump format, quad math; env-gated `PreviewRealDataTests`
  verified against the real install (172,750 entries, 869,687 records,
  `logs/preview-dds.png` + `logs/preview-nif.png`). Doc:
  [asset preview GUI](/tools/preview-gui.md). Item 2.10 left
  [todo](/todo.md).

## 2026-07-17

* **CLI dev tool** (2.9, complete): new `openskycli` command-line target
  sharing the engine sources via a synchronized-group exception set
  (app-only files excluded); entry code in `openskycli/`. Subcommands:
  `vfs ls`/`vfs cat` (new `VirtualFileSystem.archiveEntries()`, tested),
  `record` (FormID/EDID lookup + decoded dump), `cell` (Metal-free
  exterior-cell summary), `nif`/`dds` (parser-eye asset inspection),
  `render` (offscreen cell -> PNG via `Renderer.renderOffscreen`).
  `make cli` builds; env-gated `make probe` (`tools/probe.sh`) smoke-runs
  all commands against the local install, self-skips without game data,
  logs to `logs/`. Verified on the real install: cell/record match the
  first-render-cell decision (16 refs, 15 STAT), render PNG shows the
  Whiterun walls (4.3% non-background). stdlib arg parsing —
  swift-argument-parser rejected while the surface stays small. Doc:
  [CLI dev tool](/tools/cli.md). Item 2.9 left [todo](/todo.md).
* **Item 2.8 complete — free-fly camera**: fly the rendered cell with
  WASDQE + mouse-look. New `FreeFlyCamera` (pure pose -> view matrix +
  per-frame integration; yaw about +Z, pitch clamped +/-89 deg) and
  `CameraInputState` (logical pressed-key/pointer/boost state) — both
  AppKit-free, unit-tested (`FreeFlyCameraTests`, `CameraInputStateTests`):
  orientation vs conventions, pitch clamp, movement direction relative to
  yaw, boost, seed reproduces the 2.7 framing view. Input capture in new
  `GameMetalView` (MTKView subclass): NSEvent key/pointer -> state, click
  grabs pointer (`NSCursor.hide` + `CGAssociateMouseAndMouseCursorPosition`),
  Esc/focus-loss releases. `Renderer` holds a live camera seeded from the
  injected `SceneCamera`, advances it each frame with real clamped `dt`;
  nil input (offscreen/tests) -> static seeded pose, so offscreen tests
  unchanged. Speeds: base 1800 units/s (~2.3 s per 4096-unit cell), Shift
  x3.5. Doc: [free-fly camera](/engine/free-fly-camera.md). Item 2.8 left
  [todo](/todo.md).
* **Item 2.7 complete + coordinate decisions final**: real-data render of
  `WhiterunExterior06` verified visually (offscreen PNG) — 16 refs, 15
  drawn, 1 non-STAT skip, 0 missing textures; wall runs join correctly,
  nothing inside-out -> winding + REFR euler sign/order in
  [coordinates](/decisions/coordinates.md) upgraded from provisional to
  final. Item 2.7 left [todo](/todo.md).
* **Cell render at launch** (2.7 app wiring, part 2): AppDelegate locates
  game data before window content, wires a scene factory into
  `GameViewController` (runs on the view's Metal device): VFS ->
  `ESMFile` -> `TextureLibrary` -> `MeshLibrary` -> `CellSceneBuilder` ->
  `SceneCamera.framing(bounds:)` -> injected `Renderer`. Target constants
  centralized in `opensky/FirstRenderCell.swift` (Tamriel (6,-2)). Any
  factory failure -> `[ERROR]` log + DemoScene fallback, never crash;
  build synchronous at startup (fine for one small cell). New env-gated
  `CellRenderRealDataTests`: real-install build + offscreen render +
  `logs/cell-whiterunexterior06.png`, auto-skips without
  `OPENSKY_DATA_ROOT`. Doc: [cell scene build](/engine/cell-scene.md).
* **Scene + camera injection** (2.7 app wiring, part 1): `Renderer` init
  is now `init(view:scene:camera:)` — optional prepared `RenderScene` +
  `SceneCamera`; nil -> DemoScene + `.demo` camera, so existing tests/CI
  run unchanged. `updateFrameUniforms` reads the stored camera, per-draw
  ring sized off the injected scene. New `SceneCamera`
  (`opensky/Rendering/`): `.demo` constants + `framing(bounds:)` — frames
  a Z-up AABB from south-west/above at `radius / sin(fovY/2) * 1.1`,
  min 64 units; unit-tested. Doc:
  [Metal 4 renderer](/rendering/metal4-renderer.md).
* **Cell scene build** (2.7): new `opensky/World/` — `CellSceneBuilder`
  walks WRLD top group -> world children -> exterior blocks (labels
  ignored, XCLC decoded) -> CELL + children -> persistent/temporary REFR
  records; STAT index (lazy, raw FormIDs, single plugin); instances via
  `MatrixMath.placement`, sorted by (mesh path, FormID) -> adjacent per
  model (instancing-ready) -> opaque-first `RenderScene`. Robustness:
  per-ref/asset failures log + skip + count (malformed / non-STAT /
  marker / load-failed buckets), only worldspace/cell absence throws;
  `CellLoadSummary.summaryLine` one-liner after load. `MeshLibrary` now
  records a model-space `ModelBounds` AABB at parse time ->
  `CellScene.bounds` world AABB for camera framing. Doc:
  [cell scene build](/engine/cell-scene.md).
* **First-render-cell decision** (2.7): probe over Tamriel grid box
  [-2,10]x[-9,3] (170 cells, 9 720 STATs) -> target = `WhiterunExterior06`
  at (6,-2): 16 refs, 94% STAT, 8 distinct models, all VFS-resolvable,
  recognizable Whiterun walls. Farm cells rejected (127-153 refs, 28-34
  models). Probe fact binding scene build: STAT MODL paths carry no
  `meshes\` prefix, VFS keys do -> prepend before lookup. Doc:
  [first render cell](/decisions/first-render-cell.md).

## 2026-07-10

* **Winding decision corrected by observation** (2.6): demo ground plane
  (only single-sided flat mesh) culled away under the provisional
  `.clockwise` front — closed boxes masked it by showing interior faces.
  Front = counter-clockwise seen from outside (right-hand-rule outward
  normals), cull back; matches OpenMW's GL rendering of the same content.
  [Coordinates](/decisions/coordinates.md) winding section rewritten,
  no longer provisional; re-verify against vanilla NIFs at 2.7.
* **Static-mesh render path** (2.6): triangle placeholder replaced.
  Opaque + alpha-test pipeline variants (function constant, one fragment
  fn); `FrameUniforms`/`DrawUniforms` 256-byte-aligned rings (per-draw
  ring = slots x drawCount); binds via one `MTL4ArgumentTable` (state
  captured per draw); trilinear+aniso repeat sampler; depth32Float +
  less/write; per-draw cull-none for double-sided. `FrameStats` logs
  per-120-frame window (frame interval/fps, CPU encode, GPU ms via
  `MTL4CounterHeap` timestamps + `sampleTimestamps` correlation) — the
  2.9 fps gate measure. `Renderer.renderOffscreen` renders one frame
  synchronously into an owned target: deterministic pixel tests + PNG,
  future 2.9 screenshot. Windowless `MTKView.currentDrawable` crashes in
  `waitForDrawable` -> never test through drawables (`docs/testing.md`).
  Scene types: `StaticVertexLayout` (48-byte interleave + descriptor),
  `RenderMesh`/`RenderModel`/`RenderScene` (opaque-first draw lists,
  residency dedup), `DemoScene` (synthetic proving scene, throwaway at
  2.7). Doc: [Metal 4 static-mesh renderer](/rendering/metal4-renderer.md).
  Item 2.6 complete -> left [todo](/todo.md).

* **DDS probe acceptance** (2.5): swept all 32 920 `.dds` in the local
  install's BSAs — 22 636 BCn parsed clean (BC3 18 074 / BC1 4 417 /
  BC2 145; vanilla has zero DX10/BC7 files), 10 284 rejected with typed
  errors as designed (10 225 uncompressed RGB face/tint/UI art, 58
  cubemaps, 1 volume -> placeholder path). Max dim 8192 -> fixed stale
  4096 comment. Farmhouse set (candidate 2.7 area): 64/64 full decode +
  GPU upload. Numbers folded into
  [DDS texture container](/formats/dds.md). Item 2.5 complete -> left
  [todo](/todo.md).
* **DDS -> MTLTexture upload** (2.5): `Rendering/TextureLoader.swift` (new
  `opensky/Rendering/` dir, noted in AGENTS.md layout) — BCn
  `MTLPixelFormat` per usage (`TextureUsage.color` -> sRGB view, `.data` ->
  linear; BC4/5 have no sRGB variants), full mip chain via
  `MTLTexture.replace`, `.shared` storage (unified memory). Failure path:
  parse/upload error or missing file -> log + shared 1x1 placeholder
  (mid-gray color / flat normal), never crash. GPU tests gated on
  `supportsBCTextureCompression` (paravirtual CI GPUs lack it).
* **DDS container parser** (2.5): `Formats/DDS/DDSFile.swift` — magic +
  DDS_HEADER + optional DDS_HEADER_DXT10; FourCC DXT1/3/5, ATI1/2, BC4U/5U +
  DXGI UNORM/`_SRGB` codes -> BC1-BC5/BC7; tightly packed mip chain sliced by
  4x4-block math, `bytesPerRow` for `MTLTexture.replace`; cubemap/volume/
  array/uncompressed -> typed `unsupported`, truncated chain -> `malformed`.
  Ref: Microsoft DDS programming guide. Doc:
  [DDS texture container](/formats/dds.md).
* **NIF materials probe acceptance** (2.4): resolved materials for all
  22 196 geometry-BSA `.nif` (zero failures): 50 407 materials, 1 356
  fallback, 9 096 alpha-test, 5 329 blend, 1 362 double-sided; 99.6% of
  diffuse keys resolve in the texture BSAs after teaching `vfsKey` the
  engine's last-`textures/` truncation (vanilla ships exporter-absolute
  paths); 198 remaining misses are genuinely absent vanilla textures ->
  2.5 placeholder rule. `Model.materials` now carries resolved engine
  `Material` values (`Geometry/Material.swift`); `MaterialSlot` block refs
  replaced. Item 2.4 complete -> left [todo](/todo.md).
* **NIF material block decoders** (2.4): `Formats/NIF/NIFShaderProperty.swift`
  — BSLightingShaderProperty (Skyrim layout: shader type before the
  NiObjectNET name, flags 1/2, UV offset/scale, texture set ref, alpha,
  glossiness, specular; type-conditional tail unread);
  `NIFTextureSet.swift` — BSShaderTextureSet slots + `vfsKey(for:)` path
  normalization (lowercase, `\` -> `/`, strip `data/`, ensure `textures/`);
  `NIFAlphaProperty.swift` — AlphaFlags blend/test bits + threshold.
  `NIFObjectNET` split out of the AV prefix (property blocks lack NiAVObject
  fields). Ref: NifTools `nif.xml`. Doc: [NIF mesh](/formats/nif.md)
  materials subset.
* **NIF geometry probe acceptance** (2.3): typed decode sweep over the
  geometry BSAs (Meshes0/1, _ResourcePack) — 22 196 `.nif` through
  `NIFFile.model()`, zero errors; 51 671 meshes, 23.5 M verts, 23.3 M tris,
  5 751 skinned/empty shapes skipped. Candidate-static AABBs plausible vs
  the 4096-unit cell (farmhouse01 1409 x 705 x 744). Numbers folded into
  [NIF mesh](/formats/nif.md). Item 2.3 complete -> left [todo](/todo.md).
* **NiNode scene-graph decode** (2.3): `Formats/NIF/NIFObject.swift` — shared
  NiObjectNET + NiAVObject prefix (name via string table, flags, T/R/S,
  collision ref; Skyrim streams 83/100 only) with `localTransform` = T·R·S;
  `NIFNode.swift` — children refs, one layout for NiNode + append-only
  subclasses (BSFadeNode…), selector nodes excluded.
  `BinaryReader.readFloat32`. Ref: NifTools `nif.xml`. Doc:
  [NIF mesh](/formats/nif.md) scene-graph + NiNode sections.
* **BSTriShape geometry decode** (2.3): `Formats/NIF/NIFTriShape.swift` —
  bounding sphere, skin/shader/alpha refs, BSVertexDesc bitfield -> attribute
  flags + stride cross-check, interleaved BSVertexDataSSE records (full-float
  positions — SSE never packs them half, unlike FO4; half UVs, normbyte
  normals/tangents, split bitangent reassembled, colors; skinning/eye bytes
  skipped), validated uint16 triangle list, SSE particle trailer ignored.
  Stride/data-size mismatch -> `malformed`. Ref: NifTools `nif.xml`
  (BSVertexDataSSE, BSVertexDesc); normbyte remap per NifSkope/nifly. Doc:
  [NIF mesh](/formats/nif.md) BSTriShape section.
* **NIF scene flatten -> engine meshes** (2.3): `Geometry/Mesh.swift` — engine
  `Mesh`/`Model`/`MaterialSlot` types decoupled from disk layout;
  `Formats/NIF/NIFModel.swift` — `NIFFile.model()` walks footer roots,
  composes `parent * local` transforms, decodes BSTriShape leaves, dedups
  material slots by (shader, alpha) ref pair, skips skinned/empty shapes
  (counted), throws `malformed` on bad refs/cycles/depth > 64. New
  `opensky/Geometry/` dir noted in AGENTS.md layout. Doc:
  [NIF mesh](/formats/nif.md) "Scene graph -> engine mesh".
* **NIF container probe acceptance** (2.2): walked every `.nif` in the local
  install — 22 806 files across 8 BSAs, all parsed, zero throws. All version
  20.2.0.7 / user 12; BS stream 100 except one 83. 143 distinct block types;
  histogram + M2 coverage list folded into [NIF mesh](/formats/nif.md).
  Item 2.2 complete -> left [todo](/todo.md).
* **Lossy text decode for NIF strings** (2.2): probe over vanilla meshes hit
  exporter garbage in one string table (bytes undefined in cp1252) ->
  `GameText.decodeLossy` (UTF-8 -> cp1252 -> ISO 8859-1, never nil), used for
  NIF header strings so a junk name cannot reject a mesh. Note in
  [NIF mesh](/formats/nif.md).
* **NIF block walk** (2.2): `Formats/NIF/NIFFile.swift` — slices every block
  payload by the header size array (unknown types skipped by construction),
  reads footer roots, `blockTypeCounts()` histogram for probes. Oversized
  block / truncated footer -> `NIFError.malformed`. Doc:
  [NIF mesh](/formats/nif.md) block walk + footer sections.
* **NIF header parser** (2.2): `Formats/NIF/NIFHeader.swift` — version line,
  version (20.2.0.7 only), endian byte, user version, BSStreamHeader (83/100),
  block type table, per-block type index (PhysX bit masked) + size array,
  string table, groups. Typed `NIFError`. Ref: NifTools `nif.xml`. Doc:
  [NIF mesh](/formats/nif.md).
* **MatrixMath growth** (2.1): `zUpToYUp` basis change, `rotationX/Y/Z`,
  `scale(uniform:)`, `lookAt` (RH, works straight off Z-up world vectors),
  `placement(position:rotation:scale:)` = `T * Rz(-z) * Ry(-y) * Rx(-x) * S` for
  REFR data. Unit tests: axis mapping, det +1, eye/target properties, yaw sign,
  TRS round-trip. Item 2.1 complete -> left [todo](/todo.md).
* **Coordinates + units decision** (2.1):
  [decision doc](/decisions/coordinates.md) — world space stays Skyrim Z-up RH at
  native units, view/projection convert to Metal NDC; fixes column-major `M * v`,
  clockwise front + back cull (provisional, verify at 2.6), near 10 / far 65 536
  units, REFR euler = `Rz(−z)·Ry(−y)·Rx(−x)` (sign/order flagged for 2.7 visual
  check). Backed by probe over vanilla `Skyrim.esm`: 236 187 temporary refs in
  6 372 Tamriel exterior cells — all positions inside their 4096-unit grid square,
  all rotations within ±2π (radians).
* **Milestone structure in todo**: [todo](/todo.md) — added "Milestones at a glance"
  overview (M1 done -> M4, one goal + one gate each), gave milestone 3 a goal line,
  numbered items 3.1-3.6 and an acceptance gate 3.7 (mirrors M2's shape), marked M4 as
  direction-only pending re-scope at 3.7. Item content unchanged.
* **Headless unit-test host + testing doc**: `OpenSkyApp.main()` skips
  `AppDelegate` (window/renderer/probe) when `XCTestConfigurationFilePath` is
  set, activation policy `.prohibited` -> `make test` runs with no visible
  window. UI smoke test guards the normal launch path. Split earlier same day:
  `make test` = unit only, `make test-ui` = XCUITest suite, CI runs both.
  Doc: [testing setup](/testing.md).
* **Renderer skeleton doc**: audit of done-item wiki coverage found one gap — Metal 4
  render loop knowledge lived only in code. Added
  [Metal 4 renderer skeleton](/rendering/metal4-renderer.md) (command flow, frame pacing,
  256-byte uniform ring buffer, argument tables, residency, MatrixMath conventions);
  filled the empty Rendering section in [index](/index.md).
* **Todo hygiene rule**: AGENTS.md — done item leaves `docs/todo.md` in the same commit,
  knowledge folds into the wiki + this log; todo holds open work only. Applied to
  [todo](/todo.md): dropped "Done" + completed milestone 1 sections (history lives here,
  layouts in `docs/formats/`).
* **Milestone 2 detailed plan**: expanded [todo](/todo.md) milestone 2 into
  sequenced sub-items 2.1-2.9 (coordinates decision -> NIF container/geometry/
  materials -> DDS -> renderer -> cell scene -> camera -> acceptance) with
  per-item acceptance criteria, spec refs, probe strategy, dependency order.

## 2026-07-09

* **Record decoders + lstring wiring**: `Formats/ESM/Records/` — `Worldspace`
  (WRLD), `Cell` (CELL, both DATA sizes, 8/12-byte XCLC), `PlacedReference`
  (REFR pos/rot/scale), `StaticObject` (STAT MODL), `LString` +
  `GameData/LocalizedStrings.swift` (table lookup through the VFS, lazy per
  kind, language pick). Shared lenient decode moved to `Formats/GameText.swift`.
  Doc: [records](/formats/records.md). Milestone 1 acceptance met — probe
  listed 37 worldspaces (names via string tables), counted cells (16 978
  exterior), dumped WhiterunExterior01's 100 STAT refs with model paths.
* **Localized string tables**: `Formats/Strings/StringTable.swift` —
  `.strings`/`.dlstrings`/`.ilstrings` reader (header + directory, zstring
  vs length-prefixed framing, lenient UTF-8 -> windows-1252 decode).
  `BinaryReader.readZStringData` added for caller-chosen encodings. Doc:
  [string tables](/formats/strings.md). Verified against all 273 vanilla
  table files (10 languages, 834 865 strings, 0 failures).
* **FormID + master resolution**: `Formats/ESM/PluginHeader.swift` (TES4
  HEDR/CNAM/SNAM/MAST decode) + `FormID.swift` (`FormID`, `ResolvedFormID`,
  `FormIDResolver` — top byte -> master index, out-of-range clamped to the
  plugin, null -> nil). Doc: [FormID](/formats/formid.md). Verified against
  all five vanilla masters. Lint config: `inclusive_language` now allows
  "master" — TES4 domain term (MAST), spec traceability.
* **ESM/ESP container walk**: `Formats/ESM/` — TES4 + top-group index over a
  memory-mapped plugin, lazy GRUP/record traversal, zlib record decompression
  (`Formats/Zlib.swift` over Apple Compression), field iterator with XXXX size
  extension, shared `FourCC` type code. Doc: [ESM container](/formats/esm.md).
  Verified against vanilla Skyrim.esm (870 k records, all payloads parse).
* **VFS / resource manager**: `GameData/VirtualFileSystem.swift` +
  `ArchiveLoadOrder.swift` — one lookup layer over the data root. Loose files
  override archives, later archives override earlier, case/separator-
  insensitive keys, lazy archive open, malformed archives logged + skipped.
  Load order: ini resource lists (Skyrim.ini -> Skyrim_Default.ini -> built-in
  vanilla) then plugin-named archives. Doc: [VFS](/formats/vfs.md).
* **Game data locator**: `GameData/GameDataLocator.swift` — env var ->
  UserDefaults -> default Steam path, fail-loud alert + os_log on missing/invalid,
  no silent fallback. Doc: [game data locator](/engine/game-data-locator.md).
  Verified against real install (`/Volumes/data/steam/...`) via unified log.
* **Roadmap**: expanded [todo](/todo.md) into full milestone plan (M1 game data ->
  M4 playable) + agent handoff instructions (branch/PR state, machine quirks,
  format-work discipline).
* **BSA parser**: BSA v105 reader (`Formats/BSA/`), clean-room LZ4
  frame/block decoder, bounds-checked BinaryReader. Docs:
  [BSA format](/formats/bsa.md). Verified against vanilla SSE archives at
  runtime; synthetic-fixture unit tests.
* **macOS conversion**: iOS template -> native macOS-only app, Xcode 26.3 project
  format (objectVersion 100), programmatic AppKit + Metal 4 rotating-triangle
  skeleton, shared scheme, MatrixMath + tests. See
  [decision](/decisions/native-macos-app.md). Rewrote [todo](/todo.md) as roadmap.
* **Creation**: Initialized docs wiki and project development tooling
  (AGENTS.md, git hooks, lint/format, CI).
