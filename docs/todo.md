---
type: Task List
title: Roadmap and outstanding work
description: OpenSky mission roadmap - agent handoff, milestone plan, open questions.
tags: [meta, roadmap, planning, handoff]
timestamp: 2026-07-10T00:00:00Z
---

# TODO — roadmap

State as of 2026-07-10. Ordered by mission priority (AGENTS.md): render static world
geometry first -> grow toward playable engine.

## How to continue (agent handoff)

Fresh session picks up here. Steps:

1. Read AGENTS.md fully — it is the contract. Then this file, then `docs/log.md`.
2. `make bootstrap` once per checkout (tools, hooks, Metal Toolchain). `make check` +
   `make test` must be green before and after work.
3. Check PR state (`gh pr list`). As of 2026-07-10: PRs #1-#8 (tooling through record
   decoders — milestone 1 complete) merged to `main`. New work branches from up-to-date
   `main`.
4. Pick topmost unchecked item below. One branch per item (`feat/...`), atomic commits,
   Conventional Commit bodies (Context/Change/Rationale/Impact/Tests), PR via `gh`.
   Item done + green -> always commit and open the PR; never leave finished work
   uncommitted. No AI trailers.
5. Format work discipline: cite open spec (UESP, xEdit, NifTools) in code + doc, synthetic
   in-code test fixtures only, write `docs/formats/<name>.md`, update `docs/log.md` +
   `docs/index.md` in same commit. Never commit game data — no exceptions.
6. Rendering work: verify visually, not just green build. Screen Recording TCC missing on
   this machine -> use XCUITest screenshot (write to `FileManager.temporaryDirectory`,
   NSLog the path) or ask user to look.
7. Game data (read-only, never copied into repo/build):
   `/Volumes/data/steam/steamapps/common/Skyrim Special Edition/`. Verify parsers against
   real files via throwaway runtime probes; probes never land in commits.

Machine quirks: repo on case-insensitive external APFS volume (case-only rename needs
`git mv`; AppleDouble `._*` files ignored). Xcode 26 ships without Metal Toolchain
(`xcodebuild -downloadComponent MetalToolchain`, bootstrap handles it). GitHub
`macos-latest` currently has Xcode 26 — CI gate self-skips below 26.

## Done

* Dev tooling: Makefile hub, git hooks, SwiftFormat/SwiftLint/markdownlint/shellcheck,
  CI. `make check` green. (PR #1)
* Xcode project: native macOS-only (was iOS template), project format Xcode 26.3
  (objectVersion 100), programmatic AppKit app, shared scheme, ad-hoc signing. (PR #1)
* Metal 4 skeleton: MTL4CommandQueue/CommandBuffer/ArgumentTable/ResidencySet pipeline,
  rotating triangle renders on M1 (visually confirmed 2026-07-09). MatrixMath unit-tested.
* BSA v105 parser (`Formats/BSA/`) + clean-room LZ4 frame decoder + BinaryReader.
  Verified against vanilla SSE archives. Doc: [BSA](/formats/bsa.md). (PR #2)

## Milestone 1 — read game data

Goal: locate install, open archives + plugins, walk records. Acceptance: app (or test
probe) lists all worldspaces in `Skyrim.esm`, counts cells per worldspace, dumps one
exterior cell's STAT refs with FormIDs, positions, rotations, model paths.

* [x] Game data locator: env `OPENSKY_DATA_ROOT` -> defaults `OpenSkyDataRoot` ->
      default Steam path. Fail-loud alert + os_log, no silent fallback. Doc:
      [game data locator](/engine/game-data-locator.md).
* [x] BSA v105 archive parser. Done, see above.
* [x] VFS / resource manager: one lookup layer over data root. Loose files under `Data/`
      override BSA contents; case-insensitive keys; archive open order (vanilla masters'
      BSAs first, per Skyrim.ini `sResourceArchiveList`/`sResourceArchiveList2`, then
      plugin-named archives). Lazy archive open. Doc: [VFS](/formats/vfs.md).
* [x] ESM/ESP container walk (`Formats/ESM/`): 24-byte record headers, GRUP traversal
      (group types 0-9), zlib-decompressed records via Apple Compression (2-byte zlib
      header stripped), field iterator with XXXX size extension, lazy payload parsing.
      Verified against vanilla Skyrim.esm (870k records, 44k compressed, all fields
      parse). Doc: [ESM container](/formats/esm.md).
* [x] FormID + master resolution (`Formats/ESM/PluginHeader.swift`, `FormID.swift`):
      TES4 header decode (HEDR, CNAM/SNAM, MAST), FormID top byte -> master index,
      `ResolvedFormID` = (plugin, objectID). Doc: [FormID](/formats/formid.md).
* [x] Localized strings (`Formats/Strings/StringTable.swift`): three table formats
      (zstring vs length-prefixed framing), lenient UTF-8 -> cp1252 decode, verified
      against all 273 vanilla tables. Doc: [string tables](/formats/strings.md).
* [x] First record decoders (`Formats/ESM/Records/`): WRLD, CELL (+ XCLC grid, both
      DATA sizes), REFR (NAME base, DATA pos/rot, XSCL scale), STAT (MODL model path);
      LAND deferred to milestone 3. `LString` + `GameData/LocalizedStrings.swift` wire
      lstring -> table via VFS (language pick, default english). Doc:
      [records](/formats/records.md). Milestone acceptance verified by probe:
      37 worldspaces listed w/ localized names, cells counted per worldspace,
      WhiterunExterior01 STAT refs dumped w/ FormIDs, pos/rot, model paths.

## Milestone 2 — static world geometry (mission first target)

Goal: recognizable, textured static geometry of one exterior cell on screen, free-fly
camera, sustained >30 fps on M1. Screenshot lands in `docs/`.

Sequencing: 2.1 blocks all NIF + renderer work. 2.2 -> 2.3 -> 2.4 build on each other;
2.5 (DDS) independent, can run parallel to NIF; 2.6 needs 2.1 only; 2.7 needs 2.2-2.6;
2.8 needs 2.6 only (fly around any scene, even untextured). One branch/PR per numbered
item. Every format item: cite spec, synthetic in-code test fixtures, write/grow
`docs/formats/<name>.md`, verify against real install via throwaway probes (never
committed).

### 2.1 Coordinates + units decision (blocker)

* [ ] `docs/decisions/coordinates.md`: Skyrim world = Z-up right-handed, 1 unit ~1.428 cm
      (~70 units/m); Metal NDC = y-up, z [0,1]. Suggested decision: keep Skyrim axes +
      units untouched in world space; view/projection does the Z-up -> Metal conversion.
      No per-asset mesh rewrite. Decision must also fix: simd column-major `M * v`
      convention, triangle winding + cull mode after the basis change, near/far planes at
      Skyrim scale (exterior cell = 4096 units square -> far covers several cells), REFR
      euler rotation order + sign (verify against observed refs in a known cell, not from
      memory).
* [ ] MatrixMath growth + unit tests: lookAt, Skyrim -> Metal basis change, TRS compose
      from REFR data (position, euler rotation, uniform scale). Round-trip tests.

### 2.2 NIF parser — container

Refs: NifTools `nif.xml`, NifSkope source docs, UESP. SSE meshes: version 20.2.0.7,
user version 12, BS stream 100. Doc `docs/formats/nif.md` grows over 2.2-2.4.

* [ ] Header: version line, version, endianness, user version, block count, block type
      table, per-block type index + size array, string table, groups.
* [ ] Block walk with typed skip: unknown/unneeded block type -> skip via recorded block
      size, keep walking. Malformed input -> typed throw, never crash caller.
* [ ] Unit tests: synthetic NIF bytes built in code (header + minimal block table).
* [ ] Probe acceptance: walk block tables of every `.nif` in vanilla meshes BSAs without
      a throw; log histogram of block types (tells us what 2.3/2.4 must cover).

### 2.3 NIF parser — scene graph + geometry

* [ ] NiNode: name, flags, transform (translation, 3x3 rotation, uniform scale), children
      refs. Accumulate parent chain to per-shape world transform.
* [ ] BSTriShape: bounding sphere, VertexDesc 64-bit bitfield -> attribute presence +
      stride; positions (half or full float per full-precision flag), UVs (half float),
      normals/tangents (byte-packed), vertex colors; uint16 triangle list.
* [ ] Flatten to engine types decoupled from disk layout: `Mesh` = vertex/index arrays +
      per-shape transform + material slot ref. Skip skinning/animation/collision blocks.
* [ ] Unit tests: synthetic single-BSTriShape file; half-float + packed-normal decode.
* [ ] Probe: dump shape/vertex/triangle counts + AABBs for the target cell's models;
      sanity-check sizes against cell dimensions.

### 2.4 NIF parser — materials subset

* [ ] BSLightingShaderProperty: shader type, shader flags 1/2, UV offset/scale, alpha,
      glossiness, specular color/strength — parse what the shader needs, skip the rest.
* [ ] BSShaderTextureSet: path slots (slot 0 diffuse, slot 1 normal; others recorded,
      unused for now).
* [ ] NiAlphaProperty: flags -> blend/test bits + threshold (foliage needs alpha test).
* [ ] Texture path normalization to VFS keys: lowercase, `\` -> `/`, ensure `textures/`
      prefix (real files vary).

### 2.5 DDS -> MTLTexture

Ref: Microsoft DDS programming guide (`DDS_HEADER`, `DDS_HEADER_DXT10`). Doc
`docs/formats/dds.md`.

* [ ] Parser: header + optional DX10 extension; FourCC DXT1/DXT3/DXT5 + DXGI formats ->
      BC1/2/3/4/5/7; mip chain offsets via 4x4-block size math; cubemaps/volumes -> typed
      error for now.
* [ ] Upload: BCn `MTLPixelFormat` (native on Apple Silicon), full mip chain. sRGB for
      diffuse, linear for normal maps — caller decides per usage.
* [ ] Fallback: missing/unsupported texture -> 1x1 placeholder + log, never crash.
* [ ] Unit tests: synthetic DDS bytes per supported format.
* [ ] Probe: parse headers of every `.dds` in vanilla texture BSAs; full decode of the
      target cell's texture set.

### 2.6 Renderer growth

* [ ] Depth: `depth32Float` attachment + depth-stencil state; cull mode per 2.1 winding
      decision.
* [ ] Static-mesh pipeline replacing the triangle demo: vertex descriptor matching 2.3
      engine layout; `ShaderTypes.h` uniforms — per-frame (viewProjection, camera
      position, sun direction + color, ambient), per-draw (model matrix).
* [ ] Per-draw uniforms: extend the existing 256-byte-aligned ring buffer scheme to N
      draws per frame slot; residency set updated as buffers/textures are created.
* [ ] Textures: binds via MTL4ArgumentTable, mipmapped sampler (trilinear + anisotropy).
* [ ] Shader: diffuse map * (directional sun + ambient) first; alpha-test pipeline
      variant for foliage. Normal mapping is a stretch goal once tangents verified.
* [ ] Frame stats: CPU/GPU frame ms logged (os_signpost or command-buffer timestamps) —
      this is how the >30 fps acceptance gets measured, not by eye.
* [ ] Remove triangle path once mesh path proven (no dead code rule).

### 2.7 Cell scene build

* [ ] Close the target-cell open question by probe: small exterior cell, mostly STAT
      refs, few distinct models (candidate area: Whiterun plains farm/road cells). Record
      choice + criteria in `docs/decisions/first-render-cell.md`.
* [ ] Asset caches: `MeshLibrary` + `TextureLibrary` keyed by normalized VFS path — load
      once, share across refs.
* [ ] Scene build: cell REFR list -> STAT via FormID resolver -> MODL path -> NIF + DDS
      through VFS -> instance transform (REFR position/rotation + XSCL) -> draw list
      grouped by mesh (instancing-ready).
* [ ] Robustness: missing/malformed asset -> log + skip + count; one summary line after
      load (N refs, M drawn, K skipped). Never crash on bad data (mod-quirk rule).
* [ ] Draw opaque first; alpha-test pass second if the chosen cell has foliage.

### 2.8 Free-fly camera

* [ ] Input: WASD + QE vertical, mouse look via NSEvent deltas (cursor capture, Esc
      releases), Shift speed boost. GameController support later.
* [ ] Camera state -> view matrix per 2.1 conventions; clamp pitch; move speeds tuned to
      Skyrim scale (cell = 4096 units — crossing one should take seconds, not minutes).

### 2.9 Milestone acceptance

* [ ] Target cell renders textured + recognizable; free-fly through it; sustained
      >30 fps on M1 measured via 2.6 frame stats (not eyeballed).
* [ ] Screenshot of rendered frame committed under `docs/` (engine output, not extracted
      game data); `docs/log.md` + this file updated; milestone 3 items re-checked against
      what 2.x actually built.

## Milestone 3 — world streaming + environment

* [ ] Terrain: LAND records (33x33 height grid per cell, VNML normals, texture layers
      BTXT/ATXT/VTXT), stitch neighbor cells, blend layers in shader.
* [ ] Cell streaming: load grid around camera (uGridsToLoad-style 5x5), async load,
      unload behind.
* [ ] Distant LOD: BTO/BTR terrain+object LOD meshes, LOD textures.
* [ ] Sky dome, day/night gradient; water plane w/ simple shader.
* [ ] Interior cells + door teleport (REFR XTEL).
* [ ] Lighting pass: cell lighting templates, point lights (LIGH), image-based tweaks.

## Milestone 4+ — toward playable (far out)

* Collision + character controller (walk on terrain first; HKX collision reversing later).
* Animation: HKX (Havok) reversing — hardest format; consider skeleton-only first.
* Papyrus VM: PEX bytecode interpreter (open docs exist), event dispatch.
* Audio: .fuz (lip + xwm), xwm via AVFoundation/ffmpeg-free route to be researched.
* UI: game HUD/menus are Scaleform SWF — likely custom native UI instead; decide.

## Tooling / meta

* [ ] Decide `.metal` formatter/linter (clang-format?) — AGENTS.md wants both for every
      language; document exception if none fits.
* [ ] Commit-msg hook checks subject only; body sections enforced by review.
* [ ] Test probe harness: repeatable `make`-driven way to run read-only checks against the
      local install (env-gated, skipped when data absent) instead of throwaway probes.

## Open questions

* String encoding in BSA/ESM: windows-1252 vs UTF-8 (mods vary). Current: cp1252 in BSA.
  Decide lenient decode strategy engine-wide.
* Which exterior cell as first render target — closed by milestone item 2.7 (probe-driven
  pick, recorded in `docs/decisions/first-render-cell.md`).
* Plugin load order source: hardcode vanilla masters first; `plugins.txt` support later?
