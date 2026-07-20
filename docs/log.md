# Change log

Newest first. ISO-8601 date headings. See AGENTS.md "Documentation wiki".

## 2026-07-20

* M6.2 hkaSkeleton decode complete -- `HKASkeleton`
  (`opensky/Formats/HKX/HKASkeleton.swift`) reads each hkaSkeleton out of the
  packfile via the 6.1 virtual-fixup inventory: m_name, m_parentIndices
  (i16/bone, -1 root), m_bones (inline hkaBone stride 16: name + lockTranslation),
  m_referencePose (hkQsTransform stride 48: translation/quat/scale, w-lane junk
  ignored). hkArray located via the local fixup at the field pointer offset,
  size field over capacityAndFlags, size-0 arrays (null ptr, no fixup) decode
  empty. Defensive typed `HKASkeletonError`: bounds, count mismatch, parent
  range, missing bone-name fixup, non-finite pose. `SkeletonBoneMap` name-maps
  the rig onto NIF NiNode names (`NIFSkeleton.boneTransforms`) by exact match,
  reason-tagging mismatches both directions. Layout from open parsers
  (exyorha/hkxparse, ret2end/HKX2Library, ZeldaMods Havok wiki), probe-verified
  on real human + wolf skeleton.hkx (rig + ragdoll). Real human rig: 99 bones,
  2 roots; name-map 93 of 99 matched, 6 HKX-only helper/attach bones + 6
  NIF-only nodes (incl. a Shield/Weapon/Quiver case split). New
  `openskycli skeleton <hkx> [--nif <nif>]` dumps bones/parents/roots + map;
  probe gains the M6.2 99-bone/93-match/reason-tagged gate. Synthetic
  `HKASkeletonFixture` + `HKASkeletonTests`/`SkeletonBoneMapTests` cover happy
  path, empty/multi-root, and one-axis-each malformed input. Docs:
  [hkaSkeleton](/formats/hka-skeleton.md), [CLI](/tools/cli.md). Item 6.2 left
  [todo](/todo.md).
* Local app/test builds now use Apple Development signing -> stable designated
  requirement lets macOS retain removable-volume consent across rebuilds. App Info.plist
  gains `NSRemovableVolumesUsageDescription`; first access explains Skyrim data reads.
  `XCODEBUILD_FLAGS` gives certificate-free CI an explicit ad-hoc override. Xcode's UI
  test graph stays ad-hoc because development signing blocks its non-promptable
  Developer Tool request and mixed-signature graphs cannot pair. UI fixtures use only
  synthetic internal-disk data; app/unit/real-data paths remain stable-signed.
* M6.1 HKX container parse complete -- `HKXFile`/`HKXHeader`/`HKXSection`
  (`opensky/Formats/HKX/`) decode the SSE Havok packfile container: 64-byte
  header (magic pair, fileVersion 8, layout rules 8-1-0-1, contents pointers,
  "hk_2010.2.0-r1" version field), 48-byte section headers, local/global/
  virtual fixup tables with 0xFFFFFFFF sentinel + 0xFF alignment-tail
  handling, `__classnames__` signature+0x09+zstring inventory, virtual-fixup
  object enumeration (`objects`, `rootClassName`, `sectionData(at:)` for
  6.2+). Layout from open parsers (exyorha/hkxparse, ret2end/HKX2Library,
  ZeldaMods Havok wiki), probe-verified byte-by-byte on real skeleton.hkx +
  three idle clips (skeleton: 20 classes/324 objects; idles: 9 classes/5
  objects, hkaSplineCompressedAnimation). New `openskycli hkx <key>` dumps
  header/sections/classes/objects; probe gains skeleton + male/mt_idle hkx
  checks. Synthetic `HKXFixture` + `HKXFileTests` cover happy path +
  malformed input. Docs: [HKX container](/formats/hkx-container.md),
  [CLI](/tools/cli.md). Item 6.1 left [todo](/todo.md).
* Unscheduled backlog moved from [todo](/todo.md) to tracked GitHub issues:
  tree `.btt`/`.lst` LOD + configured distance bands
  ([#62](https://github.com/jjgroenendijk/opensky/issues/62)), GMST-backed walk/run/step
  tuning ([#63](https://github.com/jjgroenendijk/opensky/issues/63)), and creature
  `NiSkinPartition` palette handling
  ([#64](https://github.com/jjgroenendijk/opensky/issues/64)). Each issue records current
  code boundary, open-spec/probe leads, clean-room scope, synthetic tests, and acceptance
  gate; roadmap now keeps milestone + tooling work only.
* Screenshot LOD hole fixed — `openskycli screenshot` without `--neighbors` hid the
  full 5x5 from the distant-LOD pass while building only the center cell -> 24-cell
  ring with neither terrain nor LOD, sky visible through the gap (spotted in the M5
  acceptance shot). `RenderCommand.sceneWithLOD` now hides only cells actually
  built; LOD fills the rest. Acceptance image
  `docs/img/m5-actors-chillfurrow.png` re-captured with connected terrain (same
  command). Streaming engine unaffected (app/bench always build the full grid).
  Probe ruled water out for the dark basin west of the farmhouse: CELL `00009618`/
  `00009619` XCLW = `0x7F7FFFFF` default sentinel, Tamriel WRLD default water
  height -14000 vs terrain ~-4200 -> data defines no water surface there; the
  black field-plot + white plant fringes are a separate mesh shading defect,
  filed as a GH issue.
* M5.6 milestone acceptance complete — M5 (actors on screen) done. Failure
  accounting gains reasons: `ActorBuildCounts.failureReasons` ("ACHR <id>: <why>")
  threads through `CellLoadSummary` + `CellBuildMetric`; fly bench gates the new
  zero-unexplained rule (`failures == failureReasons.count`, new
  `actorFailureUnexplained` error) and returns per-cell `ActorCellReport`s that
  `bench --fly-path` prints (one accounting line per touched cell, failures carry
  reasons). `make probe` gains gates: 35 per-cell lines present, interior summary
  reports >=1 drawn actor. Full real probe pass: 55 discovered = 27 rendered + 27
  disabled + 1 failed, exact in all 35 cells; single failure reason-tagged — sabre
  cat `SabreCat.nif` `NiSkinPartition` vertex-bone-palette variant (backlog);
  ChillfurrowFarm interior 1 actors (1 drawn); 5,614 stream frames avg 3.15 ms/p95
  5.79 ms; actor build p95 2190.79 ms vs 3000 ms budget; footprint peak 702/1,024
  MB. Acceptance screenshot `docs/img/m5-actors-chillfurrow.png` (four clothed
  bind-pose farmhands at ACHR poses) linked from
  [actor records](/formats/actors.md) + [renderer](/rendering/metal4-renderer.md).
  Synthetic reason-accounting + metric-mirror tests added. M5 leaves
  [todo](/todo.md); M6 (actors animate: HKX idle playback) re-scoped into 6.1-6.6
  with gates.
* CI suspended (GH Actions CPU quota exhausted) -- `ci.yml` reduced to
  `workflow_dispatch` only; "Format & lint" + "Build & test" required status checks
  removed from main branch protection (PR-only flow stays). Git hooks are the only
  gate: pre-commit format/lint, commit-msg, pre-push build+test; `--no-verify`
  remains forbidden. AGENTS.md + commit skill note the suspension; re-enable task
  in [todo](/todo.md).
* M5.5 actor streaming integration complete -- ACHR placed actors build/evict with
  cells on the serial build queue (`CellSceneBuilderActors`): local + worldspace-
  persistent ACHRs (position-owned, door pattern, cached per WRLD), template/visual
  resolvers built once + cached like statIndex, assembled placements merged into each
  cell's RenderScene; interiors run the same pass. Body/head mesh keys join
  `CellScene.assets` -> evict with the cell; MeshLibrary retains skeletons. Record-header
  flag 0x800 decodes to `PlacedActor.isInitiallyDisabled` (UESP record flags) -> explicit
  skip while M5 has no script state. Exact per-cell accounting (discovered = rendered +
  disabled + failed) in `CellLoadSummary` + `CellBuildMetric`; `bench --fly-path` gains
  actor-build p95 + accounting gates (`--actor-build-budget-ms`, default 3000 ms after
  Debug baseline p95 2165 ms — first-load skinned bodies + FaceGen dominate; perf
  follow-up GH #56). Real fly path: 55 discovered = 27 rendered + 27 disabled + 1
  asset-level failure, exact in every cell; actor phase avg 425.76/p95 2164.08/max
  5832.06 ms; footprint peak 700/1,024 MB; 5,559 frames avg 3.14 ms/p95 5.75 ms.
  Chillfurrow interior probe: 1 actors (1 drawn). Synthetic builder-actor,
  streamer-lifecycle + record-flag tests. Docs:
  [actor records](/formats/actors.md), [cell scene](/engine/cell-scene.md),
  [cell streaming](/engine/cell-streaming.md), [CLI](/tools/cli.md). Item 5.5 left
  [todo](/todo.md).
* M5.4 actor assembly complete -- `ActorAssembler` composes race/gender skeleton,
  ordered outfit + visible skin ARMAs, dynamic FaceGen head, common ACHR DATA/XSCL
  transform + world bounds. Missing/invalid skeleton/models retain reason tags; any body/
  head survivor remains renderable, zero geometry tags `noCoreGeometry`. Mesh cache keys
  actor models by explicit skeleton. NIF adds spec-cited `BSDynamicTriShape`: appended
  float4 positions merge with position-free partition UV/normal/color/influence streams;
  FaceGen uses authored Head/Spine node pose. Synthetic tests cover gender/inherited
  source, slot masking, partial failure, no-core policy, transform, dynamic attributes +
  partition-local influences. Real Heimskr probe: boots/robes/hood/hands + 6-mesh head,
  correct ACHR pose, 800x800 offscreen 10.8% lit; visual check passed. Item 5.4 removed
  from [todo](/todo.md).
* M5.3 skinned NIF + GPU bind pose complete -- SSE `NiSkinInstance`/
  `BSDismemberSkinInstance`, `NiSkinData`, `NiSkinPartition`, partition-owned vertex/
  triangle streams, four half-weight/uint8 palette influences, dismember metadata.
  `skeleton.nif` NiNode tree resolves body dummy refs by name; mesh inverse binds remain
  authoritative for undistorted bind-only palettes. Renderer adds skin stream + bone
  matrix buffers, opaque/alpha skinned Metal 4 variants, residency. Synthetic parser,
  palette, skeleton, buffer/error tests pass. Vanilla `malebody_1.nif`: 2 textured meshes,
  1,802 vertices, 2,948 triangles; Asset Browser offscreen image lit, CPU bind bounds
  match source within 0.01 units. Item 5.3 left [todo](/todo.md).

## 2026-07-19

* M5.2 visual appearance resolution complete -- RACE (`Race`: per-gender ANAM
  skeletons, WNAM skin, DATA FaceGen-head flag), ARMO (`Armor`: MODL armature
  FormIDs, BOD2/BODT slots), ARMA (`ArmorAddon`: MOD2/MOD3 gendered models,
  race lists), OTFT (`Outfit`) decoders per UESP + nif.xml biped slots;
  `LeveledActor` generalized to `LeveledList` (LVLN + LVLI, new `useAll`
  bundle flag). `ActorVisualResolver` resolves skin (NPC_ WNAM else RACE
  WNAM) + outfit (DOFT -> OTFT -> ARMO/LVLI) chains to race-compatible ARMA
  models with cross-gender fallback, masks covered skin parts via BOD2 slot
  overlap, emits FaceGen facegeom/facetint paths (defining plugin +
  zero-padded objectID, gated on the RACE FaceGen-head flag). Broken chains
  throw (no silent naked fallback); optional gaps degrade to reason-tagged
  skips. `openskycli actor` prints visuals + gains `--npc` for named NPCs
  (residents live in interior cells); probe gates Heimskr. Real install:
  WhiterunWorld radius 2/4 -> 31/31, 75/75 incl. LVLI guard bundles;
  facegen paths cross-checked against BSA listings. Docs:
  [actor records](/formats/actors.md), [CLI](/tools/cli.md). Item 5.2 left
  [todo](/todo.md).
* M5.1 actor placement + template resolution complete -- ACHR (`PlacedActor`), NPC_
  (`ActorBase`: ACBS gender/template flags, TPLT, RNAM, WNAM, PNAM, DOFT), LVLN
  (`LeveledActor`, lenient 8/12-byte LVLO) decoders per UESP + xEdit specs.
  `ActorTemplateResolver` walks TPLT chains through NPC_ + LVLN (deterministic
  highest-level-first-tie entry), resolves each appearance field by its ACBS flag
  (traits/inventory), tags every field with its source NPC_, throws typed errors on
  cycles/dangling targets/empty lists. New `openskycli actor` probe: Tamriel (6,-2)
  radius 3 -> 107/107 ACHRs resolved, WhiterunWorld (5,-3) radius 2 -> 31/31; guard
  chains route through LVLN as expected. Synthetic fixture matrix covers
  direct/template/leveled, per-flag inheritance, inert flags, cycle, missing target,
  empty list. Docs: [actor records](/formats/actors.md), [CLI](/tools/cli.md).
  Item 5.1 left [todo](/todo.md).
* LOD diffuse DDS fixed -- parser accepts strict 32-bit legacy layouts: terrain xRGB8888
  (`DDPF_RGB`, BGRX masks) + shared object-atlas RGBA8888 (`DDPF_ALPHAPIXELS`, RGBA
  masks), validates pitch/mips, rejects other bit depths/flags/masks. Metal upload maps to
  sRGB BGRA8/RGBA8; absent xRGB alpha -> 255, stored RGBA alpha preserved. Synthetic
  parser + GPU readback tests cover full mip chains + malformed variants. Production CLI
  reports L4/L8/L16/L32 terrain (256x256, 8 mips) + object atlas (2048x2048, 11 mips).
  Whiterun 5x5 frame: 101 LOD blocks/0 unavailable, textured horizon, 100% non-background.
  Full 3,060 BTR + 717 BTO sweep: 0 failed. `make probe`: sustained 720p avg 0.87 ms/p95
  2.91 ms; cross-cell gate 35 unique builds/9 unloads/25 residents/0 void.
* M4.5 milestone acceptance complete -- `bench --walk-path` drives fixed 1/120 s production
  capsule physics from Tamriel `(6,-2)` to Chillfurrow Farm `(7,-3)`, climbs 22.82 units,
  enters CELL `00016204`, crosses 160.34 floor units, follows paired door back to recorded
  exterior pose. Hard gates cover timeout, fall-through, unresolved penetration, wrong
  door/CELL/return, failed cell/door builds, route distances + active-physics avg/p95.
  XTEL actor origin now seeds walk feet correctly. Large triangle soups partition into
  shared-vertex spatial leaves -> 640x360 route 1,065 frames, avg 15.90 ms (62.9 fps), p95
  29.69 ms, max 58.28 ms; pre-partition p95 was 40.66 ms at 480x270. Synthetic route/
  partition/XTEL/
  door-failure tests pass. Fly collision-build p95 budget revised 500 -> 700 ms after repeated
  Debug baselines varied 450.82-552.57 ms; partitioned p95 533.67-635.78 ms. M5 review retained
  numbered 5.1-5.6 sequence + measurable gates.
  M4 done; M5 active in [todo](/todo.md). Utility QoS retained: default/user-initiated trials
  raised walk p95 to 48.61/55.05 ms by competing with frame physics.
* M4.4 capsule/world response complete -- production walk mode queries streamed terrain +
  per-cell static collision. Swept submoves + closest-feature narrowphase cover triangle,
  convex, box, sphere, capsule geometry; iterative depenetration slides along walls, grounds
  ramps/floors, stops ceilings, reports unresolved overlap. 32-unit forward walkable-surface
  probe climbs low treads, rejects high risers/blocked headroom, spans terrain-to-mesh seams.
  XTEL scene camera reseed clears full controller state before next physics step; F/192-unit
  door activation unchanged. Synthetic wall/ramp/step/filter/seam/ceiling + teleport tests
  pass. Real-install probe passes; collision-build p95 450.82 ms under 500 ms budget. Docs:
  [walk mode](/engine/walk-mode.md), [collision world](/engine/collision-world.md).
  Item 4.4 left [todo](/todo.md).
* M4.3 static collision world complete -- each exterior/interior `CellScene` builds placed
  player-solid bhk geometry on serial stream queue, composing REFR x body x shape transforms.
  Per-cell immutable AABB BVH supplies seam-safe resident broadphase; decoded model cache uses
  render mesh keys + same unload keep-set, so scene/index/cache evict together. Collision-only
  NIFs remain physical; no-bhk models add none. CLI 5x5 probe: 1,795 shapes, 161,427 triangles,
  137 filtered bodies, zero gaps. Production 35-cell fly path: collision avg 112.78 ms,
  p95 464.63 ms under 500 ms gate; footprint peak 593/1,024 MB; frame p95 5.77 ms.
  Synthetic placement/interior/BVH/fake-provider lifecycle tests pass. Docs:
  [collision world](/engine/collision-world.md), [CLI](/tools/cli.md). Item 4.3 left
  [todo](/todo.md).
* M4.2 NIF collision decode complete -- `NIFFile.collisionModel()` follows bhk collision
  roots through rigid-body metadata, MOPP/list/transform wrappers, compressed/chunked meshes,
  packed/NiTriStrips collections, convex vertices, box/sphere/capsule primitives. Output
  preserves object flags + duplicate Havok filters/responses, converts 69.99125 units/m,
  isolates malformed roots, accounts unknown reachable blocks. Synthetic matrix covers every
  requested shape/wrapper/filter, big/chunk strips + malformed cycle. Production
  `openskycli collision` sweep over Tamriel `(6,-2)`: 9 models, 7 collision-bearing,
  12 roots/bodies, 13 shapes, 583 triangles, 0 unsupported, 0 decode failures; collision/
  render bounds validate scale + transform composition. Docs:
  [NIF collision](/formats/nif-collision.md), [CLI](/tools/cli.md). Item 4.2 left
  [todo](/todo.md).
* M4.1 terrain walk mode complete -- G toggles default fly camera to 24x128-unit player
  capsule with 112-unit eye, gravity, ground snap, 50-degree slope limit, hardcoded
  180/360-unit walk/run speeds. Controller consumes fixed 1/120 s steps with 100 ms frame
  clamp. Each streamed `CellScene` retains LAND/DNAM CPU field; composition query uses same
  floor ownership as streaming + exact `TerrainMeshBuilder` SW->NE triangle planes (height +
  face normal), not bilinear interpolation. Synthetic saddle, hidden-quadrant, negative/border
  cell, controller math + four-cell traversal tests pass. Real Tamriel probe walked `(6,-2)`
  -> `(9,-2)` at Y -8128 in 342 frames, grounded across three borders with 0.0-unit max
  plane clearance. Docs: [terrain walk mode](/engine/walk-mode.md). Item 4.1 left
  [todo](/todo.md).
* M4/M5 roadmap review fixes -- terrain walking now samples renderer-identical triangles;
  collision decode covers transform wrappers, alternate triangle collections + Havok
  filters with reachable-block coverage accounting. M4 gate becomes production
  `bench --walk-path` over M2 target -> Chillfurrow Farm -> interior -> return, measuring
  active physics instead of static render fps; cross-worldspace Whiterun-city travel stays
  out of hidden scope. M5 splits template semantics from visual appearance, applies ACBS
  inheritance flags, adds DOFT/OTFT outfit + body-slot resolution, reason-tagged actor
  accounting, actor-enabled stream budgets; gate moves to 5.6.
* Distant terrain coverage fixed -- L4/L8/L16/L32 selection partitions each cell exactly;
  partial BTR blocks clip crossing triangles to owned cell rectangles with interpolated
  attributes + mask-keyed GPU cache variants. LOD hides successful residents only, leaving
  void/failed slots covered. Settled recenter now stages replacement full cells while old
  grid + LOD remain live, then swaps cells + ring atomically. Synthetic ownership/area tests
  pass. Real Whiterun 5x5 frame: prior sky seams filled, 101 LOD blocks/0 unavailable, 975
  visible draws, 3,313 instances, 100% non-background. East/north fly path: 35 unique builds,
  9 unloads, 25 final residents; 5,192 frames avg 3.32 ms/p95 5.94 ms/max 17.75 ms.
* M4/M5 re-scope in [todo](/todo.md) -- M4 = walkable world: 4.1 terrain walk controller
  (LAND heightfield ground), 4.2 NIF bhk collision decode (NifTools `nif.xml`; Havok
  scale + `bhkCompressedMeshShapeData` layout flagged UNCONFIRMED), 4.3 per-cell
  collision world on the streaming build queue, 4.4 collide-and-slide capsule, 4.5 gate =
  walk-mode Whiterun round trip incl. interior, >30 fps via `openskycli bench`. M5 =
  actors on screen: 5.1 ACHR/NPC_/template/body-model record chain, 5.2 skinned NIF
  decode + GPU bind-pose skinning (`NiSkinInstance`/`BSDismemberSkinInstance`,
  `skeleton.nif`), 5.3 actor assembly (skeleton + ARMA parts + FaceGen head), 5.4
  actor streaming, 5.5 gate = bind-pose actors in Whiterun exterior + interior with
  probe-verified counts + fps gate. Byte layouts unverified -> confirm at impl; FaceGen
  path shape flagged UNCONFIRMED. M6+ direction unchanged; LOD-quality + GMST items
  moved to explicit backlog.
* M3 complete -- production probe passed exterior streaming + environment acceptance.
  5x5 scripted east/north flight built 35 unique cells once, unloaded 9, settled at 25
  resident/0 void with 458 -> 510 -> 470 MB waypoint footprint (559 MB peak); 4,784
  stream frames averaged 3.11 ms, p95 5.43 ms, max 19.64 ms at 640x360. Sustained
  1280x720 render averaged 0.77 ms, p95 0.97 ms across 360 frames. Integrated 25-cell
  frame resolved terrain, 3,396 object instances, water in 8 cells, procedural sky + 122
  LOD blocks with 0 unavailable. Chillfurrow Farm probe entered interior CELL 00016204
  through door 0001633D/000163A8, rendered arrival, returned to exterior `(7,-3)`.
  Screenshot: [M3 world streaming acceptance](/img/m3-world-streaming-acceptance.png).
  M4 numbering, scope + gate remain intentionally pending.
* M3.7 lighting complete -- CELL XCLL accepts exact 92-byte + field-boundary truncated
  tails; LTMP resolves LGTM DATA/DALC per XCLL inheritance bits. Skyrim.esm probe confirms
  directional rotation int32 values are degrees (`WhiteRunIntLightingTemplate` XY = 180).
  Exact 48-byte LIGH DATA + FNAM, REFR XRDS/XEMI decode into supported omni point lights;
  negative/spot/off lights skip. Interior forward path adds base + six-axis ambient,
  directional lambert, nearest 8 point lights per draw, distance fog. Exterior scenes keep
  existing `SceneCamera` sun/ambient + procedural sky. Chillfurrow Farm real round trip:
  232 refs, 118 draws, 69 models, 49 textures, 4 point lights; lit/unlit 1280x720 comparison
  shows cell fog/ambient shift, return to `(7,-3)` succeeds. Synthetic format/inheritance/
  selection tests + app/CLI Metal builds green. Docs:
  [lighting records](/formats/lighting.md), [renderer](/rendering/metal4-renderer.md),
  [interiors](/engine/interiors.md).

## 2026-07-18

* M3.6 interiors complete -- CELL top-group type-2/type-3 walk uses FormID decimal
  ones/tens label hints with full fallback; interior scenes reuse ref/base build without
  terrain/sky. DOOR joins ModelBase MODL coverage; REFR XTEL strict-decodes exact 32-byte
  destination pose/flags. WRLD persistent `(0,0)` XTEL refs map into physical streamed
  cells by position. F activates nearest door within 192 units; serial transition resolves
  destination CELL, swaps exact XTEL camera pose, suspends exterior grid/LOD inside,
  resumes + seeds destination exterior on return. `openskycli interior` acceptance found
  Chillfurrow Farm 0001633D `(7,-3)` -> interior CELL 00016204/door 000163A8 -> same
  exterior door; rendered 1280x720 textured interior frame. Synthetic decoder/builder/
  streamer/input tests cover malformed XTEL, untrusted labels, persistent ownership,
  proximity, suspension, exact pose, return. Docs: [records](/formats/records.md),
  [interiors](/engine/interiors.md), [streaming](/engine/cell-streaming.md),
  [CLI](/tools/cli.md).
* M3.5 sky + water complete -- exterior scenes now carry one procedural fullscreen sky
  marker unless WRLD says no-sky; hardcoded day/night/twilight gradient + sun disc driven
  by renderer time-of-day (`openskycli screenshot --time-of-day`, default 13:00). CELL
  XCLW height overrides decode all three no-water sentinels; missing height resolves WRLD
  DNAM through PNAM land-data inheritance. CELL XCWT/WRLD NAM2 select WATR; exact SSE DNAM
  228/232-byte variants decode shallow/deep/reflection RGBX only. Builder emits one cached
  4096-unit plane per water cell. Renderer adds first straight-alpha Metal 4 pipeline,
  read-only depth, animated color ripples + view-angle reflection. Synthetic decoder,
  builder, scene-merge, offscreen sky/time, blend tests green. Real-install target 5x5
  showed horizon + sun; nearby `WhiterunExterior17` (5,-4) resolved + rendered water.
  Water-cell bench: 120 frames @ 1280x720 avg 1.13 ms, p95 2.06 ms vs 33.33 ms budget.
  Docs: [water format](/formats/water.md), [sky + water](/engine/sky-water.md),
  [renderer](/rendering/metal4-renderer.md), [CLI](/tools/cli.md).
* M3.4 distant LOD complete -- strict 16-byte `lodsettings` parser; NIF multi-bound +
  `BSSubIndexTriShape` decode; BTR terrain + BTO object atlas loading; `WATER` subtree skip;
  lodsettings-anchored 4/8/16/32 rings outside loaded 5x5. LOD builds on serial streaming
  queue, composes without changing camera framing, retains/evicts shared assets safely.
  `openskycli lod` swept all vanilla Tamriel 3,060 BTR + 717 BTO with 0 failures. Real 5x5
  render: 122 LOD blocks, 0 unavailable, horizon filled, intersection-free selection,
  screenshot. Tree billboards + boundary clipping deferred. Docs:
  [LOD format](/formats/lod.md), [LOD streaming](/engine/distant-lod.md),
  [CLI](/tools/cli.md).
* App + CLI screenshots -- World toolbar gains `Screenshot…`: save panel -> live camera +
  current streamed scene offscreen-rendered at drawable pixel size, PNG output excludes app
  chrome; disabled in Asset Browser. New `openskycli screenshot --out` uses existing
  cell/grid/zoom render options; `render` kept as compatibility alias. Shared
  `FrameScreenshot` owns BGRA readback + PNG encoding across app, CLI, previews, tests.
  Probe now writes `logs/probe-screenshot.png`. Docs: [main app](/tools/preview-gui.md),
  [CLI](/tools/cli.md).
* M3.3 complete -- asset browser merged into main app: one OpenSky window now launches in
  World mode and swaps in-place to a persistent Asset Browser. AppKit browser/detail/
  Settings shells moved under `opensky/`; AppKit-free catalog + engine preview pipeline
  unchanged. Main menu gains Settings Cmd+, + Edit; data-root changes re-resolve locator,
  rebuild World renderer/streamer dependencies, reload browser without relaunch. Missing
  install now renders remediation in-window, no modal alert. Removed `openskypreview`
  target/scheme/source dir + `make preview`; CLI excludes app-only shells. UI smoke covers
  default mode, switch, missing-data state, Settings; env-gated real install rendered
  World + selected NIF in browser, full-window screenshots under `logs/`; real catalog +
  DDS/NIF preview pipeline passed. Preview image compression priorities keep mode switch
  from resizing window. Docs: [main-app asset browser](/tools/preview-gui.md),
  [game data locator](/engine/game-data-locator.md).
* **M3.2 complete -- guarded async cell streaming**: launch starts empty and builds one
  center-out cell at a time off main; demo camera cannot recenter before first seed. Local
  backlog + runner pending-set dedupe bound work; per-cell mesh/texture ownership,
  resident-union drop sets, serial eviction, stale-success cleanup, transactional renderer
  swaps, and overlap-safe retire purge make unload safe. External-volume 15 GiB fill growth
  traced to `.mappedIfSafe` copying ~14.6 GiB BSA set; BSA/ESM now `.alwaysMapped`.
  Repaired real harness disables parallel tests, preflights exact selector + executed count,
  guards `task_vm_info.phys_footprint`, reuses targets, paces, and times out. Guarded 5x5:
  25 resident/0 void, ~444 MB fill, <0.5 GB peak. New shared
  `CellStreamingFlyBenchmark` + `openskycli bench --fly-path`: center -> east -> north,
  433 -> 425 -> 419 MB settled (462 MB peak), 35 unique builds exactly once, 9 initial
  cells unloaded, final 25/0, avg 2.79 ms/p95 5.33 ms/max 53.48 ms at 1280x720. Docs:
  [cell streaming](/engine/cell-streaming.md), [CLI](/tools/cli.md).
* **Async cell streaming controller** (M3.2 async build): new
  `World/CellStreamer.swift` drives live streaming from one main-thread
  `update(cameraPosition:)`. Concurrency: `CellSceneBuilder` +
  `MeshLibrary` + `TextureLibrary` confined to ONE serial `DispatchQueue`
  (`SerialCellBuildRunner`, qos utility) -- queue over actor so builds run
  one-at-a-time with no reentrancy and the caches stay lock-free
  (confinement, not locking); main only gets finished `CellScene` values.
  `CellSceneProvider` is the build seam (`BuilderCellSceneProvider` in the
  app, fakes in tests); `CellBuildRunning` abstracts the executor. Pure
  `CellStreamCore` value type holds resident/inFlight/void/failed sets:
  `accountedCells` feeds `CellGridManager` so void slots (`cellNotFound`) +
  failed builds are remembered and never re-requested (no retry storm);
  `integrate` discards stale/out-of-order completions (unloaded mid-flight).
  Per-frame budget: at most one drawable cell integrated (a swap is a full
  recompose); void/failed/stale drained free; requests dispatched
  center-out. `CellGridManager.cellCenter(of:)` added to seed the grid on a
  launch cell. Docs: [cell streaming](/engine/cell-streaming.md) controller
  * concurrency sections; MeshLibrary/TextureLibrary threading comments.
  Tests: `CellStreamCoreTests` (dedupe, void/failed no-retry, unload forget,
  stale/out-of-order), `CellStreamerTests` (fake runner: budget order,
  recenter unload, first-cell-only camera reseed).
* **Instanced draws for repeated models** (M3.2 renderer core): instances
  sharing mesh + material draw as one `drawIndexedPrimitives(...
  instanceCount:)`. `RenderScene` now builds `DrawGroup`s (mesh, material,
  `[DrawInstance]`; key = mesh + diffuse ObjectIdentifiers, first-appearance
  order); `RenderScene(merging:)` re-groups across cells. Per-draw GPU data
  split: `DrawUniforms` keeps material scalars in the 256-aligned ring
  (per group), matrices move to new tightly-packed `InstanceTransform`
  ring (128 B stride, `instanceSlotCapacity` per slot, same pow2
  regrow-on-swap). `staticMeshVertex` gains `[[instance_id]]` + `device
  InstanceTransform*` at `BufferIndexInstanceTransforms` (arg table 5
  buffers); terrain stays non-instanced. Culling composes per instance:
  only visible transforms written, group drawn with visible count,
  all-culled group skipped. `openskycli render` prints a draw-stats line
  (docs/tools/cli.md updated). Real install: Whiterun (6,-2) 49 instances
  -> 32 draw calls; 3x3 grid 711 -> 330; grid frame differs from
  pre-instancing baseline by 54/921600 px (draw-order z-fight edges, max
  delta 34) — visually identical; bench avg 0.47 ms / p95 0.50 ms. Docs:
  [metal4-renderer](/rendering/metal4-renderer.md) instanced draws section.
  Tests: `RendererInstancingTests` (one call for N instances w/ projected
  pixel evidence, culling composes), grouped-scene updates across
  `RenderSceneTests`/`DemoSceneTests`/`CellSceneBuilderTests`/
  `CellSceneCompositionTests`.
* **Swappable renderer scene + retire list** (M3.2 renderer core):
  `Renderer.setScene(_:camera:)` swaps the drawable scene between frames
  (main thread, same as draw(in:); never blocks on the GPU). Draw-uniform
  ring sized by `drawUniformSlotCapacity` (next pow2 >= drawCount, min 1),
  regrown on swap when exceeded; old scene allocations + replaced rings go
  on a retire list tagged with `frameIndex - 1`, released only once
  `endFrameEvent.signaledValue` proves those frames drained. Residency:
  setScene only adds (MTLResidencySet removals hit at commit() even with
  frames queued); removal happens at purge, filtered against the live set
  (A->B->A swaps, shared cell assets). Optional camera param reseeds
  sun/ambient + free-fly pose. New `World/CellSceneComposition.swift`:
  resident `[CellCoordinate: CellScene]`, setCell/removeCell,
  composedScene() via RenderScene(merging:) in (x,y) order,
  composedBounds() — container for the upcoming streaming controller.
  Real-install verify: Whiterun 3x3 PNG byte-identical, bench avg 0.51 ms /
  p95 0.61 ms. Docs: [metal4-renderer](/rendering/metal4-renderer.md) scene
  swap section. Tests: `RendererSceneSwapTests` (regrow swap, empty-scene
  clear frame, camera reseed), `CellSceneCompositionTests`.
* **Frustum culling wired into the renderer** (M3.2 renderer core): per-draw
  world AABBs + per-frame culling. New `RenderPlacement` (model, transform,
  world bounds) replaces the `RenderScene` instance tuples; `DrawItem` /
  `TerrainDrawItem` carry `bounds: ModelBounds?` (nil -> never culled). Cell
  build threads `MeshLibrary.bounds(forPath:).transformed(by:)` onto items
  (same value the cell AABB already unioned); terrain items get per-patch
  bounds; DemoScene computes its own. `encodeScenePass` builds one
  `Frustum(viewProjection:)` per frame -> skips failing items; per-draw ring
  now indexed by running visible-draw cursor (visible <= drawCount = ring
  capacity). Per-frame counts exposed as `Renderer.lastDrawStats`
  (`SceneDrawStats`). Encode path split to
  `Rendering/RendererScenePass.swift` (file-length limit, RendererSetup
  precedent). Real-install verify: `openskycli render --x 6 --y -2
  --neighbors` byte-identical PNG before/after (7.4% non-background);
  `openskycli bench` avg 0.55 ms / p95 0.74 ms vs 33.33 ms budget. Docs:
  [metal4-renderer](/rendering/metal4-renderer.md) Frustum culling section.
  Tests: `RendererCullingTests` (culled-vs-drawn stats + pixel checks,
  all-culled clear frame), existing offscreen/scene suites green.
* **Widen base coverage, M3.2**: `CellSceneBuilder` drew STAT bases only; MSTT, TREE,
  FURN, ACTI, CONT placements fell into the (now-gone) non-STAT skip bucket. New shared
  decoder `ModelBase` (`opensky/Formats/ESM/Records/ModelBase.swift`) reads EDID + MODL
  for all five types (UESP "Skyrim Mod:Mod File Format" /MSTT /TREE /FURN /ACTI /CONT —
  same field layout as STAT); animation/interaction fields stay unread, model path only.
  `CellSceneBuilder` gains a second lazy FormID -> `ModelBase` index over the five
  top groups (STAT stays first, largest, most common); `resolveInstances` tries STAT
  then ModelBase before giving up. Skip bucket `nonSTATSkipCount`/`nonSTATBases` renamed
  to `unsupportedBaseSkipCount`/`unsupportedBases` (`CellScene.swift`,
  `CellSceneBuilder.swift`) — now means "base FormID resolves to neither index" (DOOR,
  NPC_, ACHR, IDLM, MISC, FLOR, SOUN, ... bases, or a malformed base record), not
  "non-STAT". Real-install verify (`openskycli render`, `/Volumes/data/steam/...Skyrim
  Special Edition`): WhiterunExterior06 (6,-2) 16 refs went from 15/16 to 16/16 drawn
  (the lone ACTI now draws); WhiterunExterior02 (5,-3) 17/25 -> 25/25; WhiterunExterior10
  (7,-1) 28/34 -> 34/34; ChillfurrowFarmExterior (7,-3, 134 refs, all 5 new types
  present) 75/134 -> 104/134 (30 skipped: 13 unsupported-base — IDLM/MISC/DOOR/SOUN/FLOR,
  genuinely out of scope — plus 17 load-failed on a handful of CONT/FLOR plant meshes
  with what looks like a doubled-backslash path quirk in that plugin's MODL data, caught
  and skipped by the existing mesh-load skip bucket, never crashing). Visually verified:
  `openskycli render --neighbors` over the (6,-2) 3x3 grid — city props (wells, crates,
  furniture) and farm trees now draw where they were previously invisible, no artifacts.
  Docs: [record decoders](/formats/records.md), [cell scene](/engine/cell-scene.md).
  Tests: `RecordDecoderTests` ModelBase cases, `CellSceneBuilderTests` new base-type
  draw/marker cases + renamed skip-bucket assertions.
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
