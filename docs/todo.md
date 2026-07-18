---
type: Task List
title: Roadmap and outstanding work
description: OpenSky mission roadmap - agent handoff, milestone plan, open questions.
tags: [meta, roadmap, planning, handoff]
timestamp: 2026-07-18T00:00:00Z
---

# TODO — roadmap

State as of 2026-07-18. Ordered by mission priority (AGENTS.md): render static world
geometry first -> grow toward playable engine.

## How to continue (agent handoff)

Fresh session picks up here. Steps:

1. Read AGENTS.md fully — it is the contract. Then this file, then `docs/log.md`.
2. `make bootstrap` once per checkout (tools, hooks, Metal Toolchain). `make check` +
   `make test` must be green before and after work.
3. Check PR state (`gh pr list`). As of 2026-07-18: PRs #1-#21 merged to `main` —
   milestone 1 (data foundation) + milestone 2 (static world geometry, camera, dev
   tools) complete. New work branches from up-to-date `main`.
4. Pick topmost unchecked item below. One branch per item (`feat/...`), atomic commits,
   Conventional Commit bodies (Context/Change/Rationale/Impact/Tests), PR via `gh`.
   Item done + green -> always commit and open the PR; never leave finished work
   uncommitted. No AI trailers. Done item leaves this file in the same commit — knowledge
   folds into wiki + `docs/log.md` (AGENTS.md rule).
5. Format work discipline: cite open spec (UESP, xEdit, NifTools) in code + doc, synthetic
   in-code test fixtures only, write `docs/formats/<name>.md`, update `docs/log.md` +
   `docs/index.md` in same commit. Never commit game data — no exceptions.
6. Rendering work: verify visually, not just green build. Screen Recording TCC missing on
   this machine -> use `Renderer.renderOffscreen` (see `RendererOffscreenTests`: pixel
   asserts + temp PNG, path printed) or ask user to look. UI-test automation mode also
   flaky here; unit-target offscreen render is the reliable path.
7. Game data (read-only, never copied into repo/build):
   `/Volumes/data/steam/steamapps/common/Skyrim Special Edition/`. Verify parsers against
   real files via throwaway runtime probes; probes never land in commits.

Machine quirks: repo on case-insensitive external APFS volume (case-only rename needs
`git mv`; AppleDouble `._*` files ignored). Xcode 26 ships without Metal Toolchain
(`xcodebuild -downloadComponent MetalToolchain`, bootstrap handles it). GitHub
`macos-latest` currently has Xcode 26 — CI gate self-skips below 26.

## Milestones at a glance

Each milestone = one goal, one measurable acceptance gate (its last numbered item). Done
milestone leaves this file; history lives in `docs/log.md` + git.

* M1 — data foundation. Done 2026-07-10 (PRs #1-#8): BSA VFS, ESM/plugin record decoders.
* M2 — static world geometry. Done 2026-07-18 (PRs #9-#21): textured
  `WhiterunExterior06` on screen, free-fly camera, bench-gated fps (avg 0.39 ms/frame @
  720p on M1, Debug), `openskycli` + `openskypreview` dev tools.
* M3 — world streaming + environment (active): roam exterior worldspace seamlessly —
  terrain, cell streaming, distant LOD, sky/water, interiors via doors. Gate: 3.7.
* M4 — toward playable (direction only): collision, animation, scripting, audio, UI.
  Re-scope after M3; no gate yet.

## Milestone 3 — world streaming + environment

Goal: roam the Tamriel exterior worldspace seamlessly — terrain under every object, cells
stream in/out around the camera, distant LOD past the loaded grid, sky + water, interiors
reachable through doors. One branch/PR per numbered item; format items follow the same
spec/fixture/doc discipline as M2 (cite spec, synthetic in-code fixtures,
`docs/formats/<name>.md`, verify via repeatable `openskycli` probes).

Items re-checked 2026-07-18 against what M2 built (2.11 gate). M2 pieces M3 leans on:
`CellSceneBuilder` (`docs/engine/cell-scene.md`) is the per-cell unit 3.2 streams;
`ESMWalk` headers-only scans suit 3.1 LAND record discovery; verification path is
`openskycli render`/`bench` + `openskypreview`, screenshot pattern as in `docs/img/`.
Ordering unchanged — terrain first (everything sits on it), streaming second, rest
after. Watch item: sky/water (3.4) is also what turns the current black background in
screenshots into a real frame.

### 3.1 Terrain

* [ ] LAND records: 33x33 height grid per cell, VNML normals, texture layers
      BTXT/ATXT/VTXT; stitch neighbor cells, blend layers in shader.

### 3.2 Cell streaming

* [ ] Load grid around camera (uGridsToLoad-style 5x5), async load, unload behind.

### 3.3 Distant LOD

* [ ] BTO/BTR terrain+object LOD meshes, LOD textures.

### 3.4 Sky + water

* [ ] Sky dome, day/night gradient; water plane w/ simple shader.

### 3.5 Interiors

* [ ] Interior cells + door teleport (REFR XTEL).

### 3.6 Lighting pass

* [ ] Cell lighting templates, point lights (LIGH), image-based tweaks.

### 3.7 Milestone acceptance

* [ ] Free-fly from the M2 target cell across the streamed grid: terrain + objects appear
      without visible pop-in gaps, LOD beyond the grid, enter one interior through a door
      and return. No crash on any vanilla cell touched; >30 fps sustained measured via
      `openskycli bench` (not eyeballed).
* [ ] Screenshot under `docs/`; `docs/log.md` + this file updated; M4 re-scoped into
      numbered items with a gate.

## Milestone 4+ — toward playable (far out)

Direction only — re-scope into numbered gated items at 3.7. Candidate order:

* Collision + character controller (walk on terrain first; HKX collision reversing later).
* Animation: HKX (Havok) reversing — hardest format; consider skeleton-only first.
* Papyrus VM: PEX bytecode interpreter (open docs exist), event dispatch.
* Audio: .fuz (lip + xwm), xwm via AVFoundation/ffmpeg-free route to be researched.
* UI: game HUD/menus are Scaleform SWF — likely custom native UI instead; decide.

## Tooling / meta

* [ ] Decide `.metal` formatter/linter (clang-format?) — AGENTS.md wants both for every
      language; document exception if none fits.
* [ ] Commit-msg hook checks subject only; body sections enforced by review.

## Open questions

* String encoding in BSA/ESM: windows-1252 vs UTF-8 (mods vary). Current: cp1252 in BSA.
  Decide lenient decode strategy engine-wide.
* Plugin load order source: hardcode vanilla masters first; `plugins.txt` support later?
