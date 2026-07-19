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
* M4 — walkable world. Done 2026-07-19: streamed terrain/static collision, fixed-step
  capsule response, walk-mode door round trip + >30 fps route gate.
* M5 — actors on screen (active): placed actors rendered as skinned meshes in bind pose.
  Gate: 5.6.
* M6+ — toward playable (direction only): animation playback, Papyrus VM, audio, UI.

## Milestone 5 — actors on screen

Goal: placed actors visible in bind pose — Whiterun stops being empty. No animation, AI,
or dialogue; static skinned bodies at ACHR poses. One branch/PR per numbered item; format
items follow `format-parser` discipline. M4.5 review retained 5.1-5.6 sequencing + measurable
gates: actor builds stay on serial cell stream path, reason-tagged exact accounting remains
mandatory, actor-enabled fly bench keeps explicit build/footprint/frame budgets.

Format leads from UESP mod-file-format pages + xEdit definitions + NifTools `nif.xml`;
byte-level layouts NOT yet verified — confirm by spec + probe at impl, flag deviations.

### 5.1 Actor placement + template resolution

* [ ] ACHR placed actor (NAME base, DATA pos/rot, XSCL — REFR-shaped; lives in CELL
      persistent + temporary children). `NPC_` base: RNAM race, TPLT template, WNAM worn
      armor, PNAM head parts, DOFT default outfit, ACBS gender + template flags. Template
      chain: TPLT -> direct NPC_ or LVLN deterministic entry policy (first/highest for
      bind-pose milestone). Resolve appearance fields individually according to ACBS
      inheritance flags (`Use Traits`, `Use Model/Animation`, `Use Inventory`, etc.);
      detect cycles + missing targets, never copy every field blindly from one template.
* [ ] Acceptance: `openskycli` actor probe lists Whiterun-area ACHRs with resolved
      base NPC_, chosen leveled entry, template chain + source of every appearance field;
      synthetic-fixture matrix covers direct/template/leveled cases, each appearance-
      relevant inheritance flag, cycle + missing target; doc `docs/formats/actors.md`.

### 5.2 Visual appearance resolution

* [ ] Resolve race per-gender skeleton; naked skin from `NPC_` WNAM else RACE WNAM -> ARMO
      armature -> ARMA per-gender MOD2/MOD3. Resolve clothes from `NPC_` DOFT -> OTFT item
      list -> ARMO armatures -> compatible ARMA models; apply BOD2/body-slot selection so
      equipped parts mask covered skin parts without duplicate geometry. Resolve FaceGen
      head from defining plugin + resolved `NPC_` local object ID; confirm directory +
      zero-padding convention against open docs + real-install probe before encoding it.
      Missing optional parts degrade by reason-tagged skip; no silent naked fallback when
      an outfit chain fails.
* [ ] Acceptance: `openskycli` actor probe resolves skeleton, skin, outfit/body slots +
      FaceGen paths for named Whiterun NPCs; synthetic fixtures cover gender, skin fallback,
      outfit/ARMO/ARMA chains, slot masking, cross-plugin identity + missing optional part.

### 5.3 Skinned NIF decode + GPU bind-pose skinning

* [ ] Decode skinning from SSE NIFs: `NiSkinInstance`/`BSDismemberSkinInstance`,
      `NiSkinData` (bone bind transforms), `NiSkinPartition` / SSE per-vertex bone
      weights+indices in `BSTriShape` vertex data (`BSVertexDesc` skinning attributes);
      `skeleton.nif` NiNode bone tree. Spec: NifTools `nif.xml`. Renderer: bone-matrix
      buffer + skinned vertex path in `Shaders.metal`, bind pose only.
* [ ] Acceptance: one vanilla body mesh renders skinned + textured (asset browser +
      offscreen probe), no distortion vs bounds; synthetic skinned-mesh fixtures; doc
      `docs/formats/nif.md` extension + renderer doc update.

### 5.4 Actor assembly

* [ ] Compose one actor: race skeleton + visible skin parts + equipped outfit ARMA parts +
      FaceGen head at ACHR world pose with XSCL scale. Missing parts degrade gracefully
      with reason-tagged counters; a partial actor remains renderable when core body/head
      policy allows it.
* [ ] Acceptance: named Whiterun NPC composed + rendered offscreen at correct world
      position, clothed under the deterministic M5 equipment policy; unit tests on assembly
      selection (gender, inherited appearance, slot masking, missing-part).

### 5.5 Actor streaming integration

* [ ] Actors build/evict with cells on the serial build queue like statics; persistent
      ACHRs mapped into streamed cells by position (pattern from door handling);
      interiors included. Shared skeleton/body assets retained across cells.
      Per-cell accounting reports non-deleted ACHRs discovered, rendered, intentionally
      skipped by reason + failed; initially-disabled actors are explicit skips while M5 has
      no quest/script state.
* [ ] Acceptance: actor-enabled streaming fly-path bench shows no render/build-latency or
      footprint budget breach; build/evict + persistent-position lifecycle tests with fake
      providers; discovered = rendered + intentional skips + failures for every cell.

### 5.6 Milestone acceptance

* [ ] Bind-pose, clothed actors render at correct positions in Whiterun exterior + one
      interior; no crash across the streamed grid. Real probe reports discovered/rendered/
      intentional-skip/failure counts for each touched cell; gate requires zero unexplained
      failures + exact accounting, not equality with raw ACHR count. Actor-enabled
      `openskycli bench --fly-path` sustains >30 fps avg + p95 within explicit build-latency
      + footprint budgets.
* [ ] Acceptance screenshot under `docs/img/`, linked from actor/renderer docs;
      `docs/log.md` + this file updated; M6 re-scoped into numbered items with a gate.

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
