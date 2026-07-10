# Change log

Newest first. ISO-8601 date headings. See AGENTS.md "Documentation wiki".

## 2026-07-10

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
