---
type: Task List
title: Roadmap and outstanding work
description: OpenSky mission roadmap - agent handoff, milestone plan, open questions.
tags: [meta, roadmap, planning, handoff]
timestamp: 2026-07-09T00:00:00Z
---

# TODO — roadmap

State as of 2026-07-09. Ordered by mission priority (AGENTS.md): render static world
geometry first -> grow toward playable engine.

## How to continue (agent handoff)

Fresh session picks up here. Steps:

1. Read AGENTS.md fully — it is the contract. Then this file, then `docs/log.md`.
2. `make bootstrap` once per checkout (tools, hooks, Metal Toolchain). `make check` +
   `make test` must be green before and after work.
3. Check PR state (`gh pr list`). As of 2026-07-09: PRs #1-#3 (tooling, BSA parser, game
   data locator) merged to `main`. New work branches from up-to-date `main`.
4. Pick topmost unchecked item below. One branch per item (`feat/...`), atomic commits,
   Conventional Commit bodies (Context/Change/Rationale/Impact/Tests), PR via `gh`.
   Commit/PR only when user asks. No AI trailers.
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
* [ ] ESM/ESP container walk: record header (24 bytes SSE: type, dataSize, flags, FormID,
      timestamp/VC, version, unknown), GRUP traversal (top groups, worldspace/cell/children
      group types 0-10), zlib-decompressed records (flag 0x40000: uint32 decompSize +
      zlib stream — Apple Compression `COMPRESSION_ZLIB` handles raw deflate; check
      header bytes), subrecord iterator (type + uint16 size, XXXX size extension).
      Lazy: index offsets, parse fields on demand. Ref: UESP "Mod File Format" + xEdit
      definitions. Doc `docs/formats/esm.md`.
* [ ] FormID + master resolution: TES4 header (HEDR, MAST/DATA), load order maps FormID
      top byte -> master index. Model in Swift as (plugin, localID) pair.
* [ ] Localized strings: TES4 flag 0x80 -> lstrings live in
      `Strings/<plugin>_<lang>.strings|.dlstrings|.ilstrings` (in BSA). Needed for names;
      parse the three table formats. Ref UESP "String Table File Format".
* [ ] First record decoders: TES4, WRLD, CELL (+ XCLC grid), REFR (NAME base, DATA
      pos/rot, XSCL scale), STAT (MODL model path), LAND deferred to milestone 3.

## Milestone 2 — static world geometry (mission first target)

Goal: recognizable, textured static geometry of one exterior cell on screen, free-fly
camera, >30 fps on M1. Screenshot lands in `docs/`.

* [ ] Coordinate + unit decision first (blocker for NIF/camera): Skyrim Z-up right-handed,
      1 unit ~ 1.428 cm; Metal NDC z [0,1]. Pick engine convention (suggest: keep Skyrim
      world axes internally, convert in view/projection), doc in
      `docs/decisions/coordinates.md`.
* [ ] NIF parser subset: header (version 20.2.0.7, BS stream 100), block table, NiNode
      transform hierarchy, BSTriShape (VertexDesc bitfield, half-float positions/UVs,
      packed normals/tangents), BSLightingShaderProperty + BSShaderTextureSet (diffuse +
      normal paths). Skip animation/collision blocks (typed skip via block sizes).
      Ref: NifTools `nif.xml`. Doc `docs/formats/nif.md`.
* [ ] DDS loader: DDS header + DX10 extension, BC1/BC3/BC4/BC5/BC7 -> `MTLTexture`
      (Metal supports BCn natively on Apple Silicon macOS), mip chain, sRGB choice per
      usage. Ref: Microsoft DDS programming guide. Doc `docs/formats/dds.md`.
* [ ] Renderer growth: depth buffer + culling, mesh vertex layouts matching BSTriShape,
      per-draw model matrix, texture binding via MTL4ArgumentTable, simple lit shader
      (directional + ambient), mipmapped sampler.
* [ ] Cell scene build: pick a small exterior cell, resolve REFR -> STAT -> NIF -> DDS
      through VFS, build instance list, draw. Missing/broken asset -> log + skip, never
      crash (mod-quirk rule).
* [ ] Free-fly camera: WASD + mouse look (NSEvent/GameController), speed modifier.

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
* Which exterior cell as first render target (small, few asset types)?
* Plugin load order source: hardcode vanilla masters first; `plugins.txt` support later?
