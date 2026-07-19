---
type: Task List
title: Roadmap and outstanding work
description: OpenSky mission roadmap - agent handoff, milestone plan, open questions.
tags: [meta, roadmap, planning, handoff]
timestamp: 2026-07-19T00:00:00Z
---

# TODO — roadmap

State as of 2026-07-19. Ordered by mission priority (AGENTS.md): render static world
geometry first -> grow toward playable engine.

## How to continue (agent handoff)

Fresh session picks up here:

1. Read AGENTS.md (the contract; lists the skills), then this file, then the newest
   2-3 entries of `docs/log.md`.
2. `make bootstrap` once per checkout. Live branch/PR state: `gh pr list` + `git log`
   — never trust a snapshot written into a doc.
3. Pick topmost unchecked item below, one branch per item. Workflows live in skills:
   `commit` (branch/commit/PR/merge), `format-parser` (format work), `probe`
   (real-data checks + render verification), `docs-wiki` (doc upkeep).
4. Game data root (read-only, never copied into repo/build):
   `/Volumes/data/steam/steamapps/common/Skyrim Special Edition/`.

Machine quirks: repo on case-insensitive external APFS volume (case-only rename needs
`git mv`; AppleDouble `._*` files ignored). Xcode 26 ships without Metal Toolchain
(bootstrap handles the download). CI gate self-skips below Xcode 26.

## Milestones at a glance

Each milestone = one goal, one measurable acceptance gate (its last numbered item). Done
milestone leaves this file; history lives in `docs/log.md` + git.

* M1 — data foundation. Done 2026-07-10 (PRs #1-#8): BSA VFS, ESM/plugin record decoders.
* M2 — static world geometry. Done 2026-07-18 (PRs #9-#21): textured
  `WhiterunExterior06` on screen, free-fly camera, bench-gated fps (avg 0.39 ms/frame @
  720p on M1, Debug), `openskycli` + main-app asset browser dev tools.
* M3 — world streaming + environment. Done 2026-07-19 (PRs #22-#35): streamed 5x5
  exterior grid, terrain, distant LOD, sky/water, lit interiors + door round trips.
* M4 — walkable world (active): collision + walk-mode player. Gate: 4.5.
* M5 — actors on screen: placed actors rendered as skinned meshes in bind pose.
  Gate: 5.5. Recheck scope at 4.5.
* M6+ — toward playable (direction only): animation playback, Papyrus VM, audio, UI.

## Milestone 4 — walkable world (collision + walk mode)

Goal: player walks instead of flying — gravity, ground under feet on terrain and meshes,
stairs climbable, walls solid, doors still work. Physical presence first; animation,
actors, scripting stay out of scope. One branch/PR per numbered item; format items follow
`format-parser` discipline (cite spec, synthetic in-code fixtures,
`docs/formats/<name>.md`, `openskycli` probes).

Format leads below from NifTools `nif.xml` + UESP; byte-level layouts NOT yet verified —
confirm against `nif.xml` definitions + real-install probe before impl, flag deviations.

### 4.1 Walk-mode controller on terrain

* [ ] Player capsule + gravity + walk/fly toggle (fly stays default dev mode). Ground =
      LAND heightfield sample (bilinear over the 33x33 grid, `docs/formats/land.md`);
      snap-to-ground, slope limit, hardcoded walk/run speeds (GMST later). Exterior
      only; cell-border crossing keeps ground contact (streamed neighbor heightfields).
* [ ] Acceptance: walk-mode traverse across >=3 streamed cells from the M2 target cell,
      camera follows terrain, no fall-through at cell seams; unit tests on heightfield
      sampling + controller math (synthetic heightfields).

### 4.2 NIF collision decode (bhk blocks)

* [ ] Parse embedded Havok collision from SSE NIFs: `bhkCollisionObject` ->
      `bhkRigidBody`/`bhkRigidBodyT` -> shape tree (`bhkMoppBvTreeShape` — skip MOPP
      bytecode, take child; `bhkCompressedMeshShape` + `bhkCompressedMeshShapeData`;
      `bhkConvexVerticesShape`; `bhkBoxShape`/`bhkSphereShape`/`bhkCapsuleShape`;
      `bhkListShape`). Spec: NifTools `nif.xml`. Output: clean Swift collision model
      (triangle soup + convex primitives) in engine units, decoupled from disk layout.
* [ ] UNCONFIRMED to chase by probe: Havok-to-engine scale factor (community value
      ~69.99 units/m), `bhkRigidBodyT` transform composition, chunked
      `bhkCompressedMeshShapeData` layout (big-tri vs chunk split).
* [ ] Acceptance: `openskycli` collision sweep over all vanilla Whiterun-cell models
      decodes without failure; synthetic-fixture unit tests per shape type; doc
      `docs/formats/nif-collision.md`.

### 4.3 Collision world + streaming integration

* [ ] Per-cell static collision set built alongside `CellScene` on the serial build
      queue (ref transform x shape, models without bhk data get none — matches vanilla).
      Spatial index per cell; evicted with cell unload; interiors included (interior
      floors are meshes, not terrain).
* [ ] Acceptance: collision stats surfaced via `openskycli` (shapes/tris per cell for
      target grid); streaming fly-path bench shows no regression breach of frame budget;
      unit tests on build/evict lifecycle with fake providers.

### 4.4 Capsule vs world response

* [ ] Collide-and-slide capsule vs terrain + mesh collision: walls block, ramps/stairs
      climb via step height, ceilings stop ascent. Door activation (F, 192 units)
      unchanged in walk mode. Deterministic unit tests: synthetic wall/ramp/stair/step
      scenes, seam crossing terrain<->mesh.

### 4.5 Milestone acceptance

* [ ] Walk-mode round trip: spawn at M2 target cell, walk Whiterun streets + stairs,
      through one door, walk the interior floor, return outside — no fall-through or
      wall clip along the route, >30 fps sustained via `openskycli bench` in walk mode.
* [ ] Screenshot under `docs/`; `docs/log.md` + this file updated; M5 re-scoped into
      confirmed numbered items with a gate.

## Milestone 5 — actors on screen

Goal: placed actors visible in bind pose — Whiterun stops being empty. No animation, AI,
or dialogue; static skinned bodies at ACHR poses. One branch/PR per numbered item; format
items follow `format-parser` discipline. Recheck sequencing at 4.5.

Format leads from UESP mod-file-format pages + xEdit definitions + NifTools `nif.xml`;
byte-level layouts NOT yet verified — confirm by spec + probe at impl, flag deviations.

### 5.1 Actor record chain decode

* [ ] ACHR placed actor (NAME base, DATA pos/rot, XSCL — REFR-shaped; lives in CELL
      persistent + temporary children). `NPC_` base: RNAM race, TPLT template, WNAM worn
      armor, PNAM head parts, ACBS flags (female bit). Template chain: TPLT -> LVLN
      leveled NPC -> deterministic entry pick (first/highest for now) or direct NPC_.
      Body model chain: NPC_ WNAM (else RACE skin) -> ARMO ARMA parts -> per-gender
      MOD2/MOD3 model paths; RACE per-gender skeleton path. Head lead: pre-generated
      FaceGen NIF `meshes/actors/character/facegendata/facegeom/<plugin>/00<formid>.nif`
      (UNCONFIRMED path shape — probe).
* [ ] Acceptance: `openskycli` actor probe lists Whiterun-area ACHRs with resolved
      skeleton + body-part model paths, template chains followed; synthetic-fixture
      tests per record; doc `docs/formats/actors.md`.

### 5.2 Skinned NIF decode + GPU bind-pose skinning

* [ ] Decode skinning from SSE NIFs: `NiSkinInstance`/`BSDismemberSkinInstance`,
      `NiSkinData` (bone bind transforms), `NiSkinPartition` / SSE per-vertex bone
      weights+indices in `BSTriShape` vertex data (`BSVertexDesc` skinning attributes);
      `skeleton.nif` NiNode bone tree. Spec: NifTools `nif.xml`. Renderer: bone-matrix
      buffer + skinned vertex path in `Shaders.metal`, bind pose only.
* [ ] Acceptance: one vanilla body mesh renders skinned + textured (asset browser +
      offscreen probe), no distortion vs bounds; synthetic skinned-mesh fixtures; doc
      `docs/formats/nif.md` extension + renderer doc update.

### 5.3 Actor assembly

* [ ] Compose one actor: race skeleton + body/hands/feet ARMA parts + FaceGen head at
      ACHR world pose with XSCL scale; missing parts degrade gracefully (skip, log).
* [ ] Acceptance: named Whiterun NPC composed + rendered offscreen at correct world
      position; unit tests on assembly selection (gender, template, missing-part).

### 5.4 Actor streaming integration

* [ ] Actors build/evict with cells on the serial build queue like statics; persistent
      ACHRs mapped into streamed cells by position (pattern from door handling);
      interiors included. Shared skeleton/body assets retained across cells.
* [ ] Acceptance: streaming fly-path bench with actors shows no frame-budget breach;
      build/evict lifecycle unit tests with fake providers.

### 5.5 Milestone acceptance

* [ ] Bind-pose actors render at correct positions in Whiterun exterior + one interior
      (probe count vs `Skyrim.esm` ACHR count for touched cells); no crash across the
      streamed grid; >30 fps sustained via `openskycli bench`.
* [ ] Screenshot under `docs/`; `docs/log.md` + this file updated; M6 re-scoped into
      numbered items with a gate.

## Milestone 6+ — toward playable (far out)

Direction only — re-scope after M5. Candidate order:

* Animation: HKX (Havok) reversing — hardest format; skeleton-only/idle first.
* Papyrus VM: PEX bytecode interpreter (open docs exist), event dispatch.
* Audio: .fuz (lip + xwm), xwm via AVFoundation/ffmpeg-free route to be researched.
* UI: game HUD/menus are Scaleform SWF — likely custom native UI instead; decide.

## Backlog (unscheduled, keep filed)

* LOD quality: tree `.btt`/`.lst` billboards; read `fBlockLevel*Distance` INI values.
* GMST-driven movement constants (walk/run speed, step height) replacing 4.1 hardcodes.

## Tooling / meta

* [ ] Decide `.metal` formatter/linter (clang-format?) — AGENTS.md wants both for every
      language; document exception if none fits.
* [ ] Commit-msg hook checks subject only; body sections enforced by review.

## Open questions

* String encoding in BSA/ESM: windows-1252 vs UTF-8 (mods vary). Current: cp1252 in BSA.
  Decide lenient decode strategy engine-wide.
* Plugin load order source: hardcode vanilla masters first; `plugins.txt` support later?
