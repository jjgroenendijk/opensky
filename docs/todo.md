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
* M2 — static world geometry (active): one textured exterior cell on screen, free-fly
  camera, >30 fps sustained on Apple M1. Gate: 2.9.
* M3 — world streaming + environment: roam exterior worldspace seamlessly — terrain,
  cell streaming, distant LOD, sky/water, interiors via doors. Gate: 3.7.
* M4 — toward playable (direction only): collision, animation, scripting, audio, UI.
  Re-scope after M3; no gate yet.

## Milestone 2 — static world geometry (mission first target)

Goal: recognizable, textured static geometry of one exterior cell on screen, free-fly
camera, sustained >30 fps on M1. Screenshot lands in `docs/`.

Sequencing: coordinate conventions fixed in `docs/decisions/coordinates.md` (2.1, done)
bind all NIF + renderer work; NIF parsing done (2.2-2.4) — `docs/formats/nif.md`
holds layouts, `NIFFile.model()` yields engine meshes with resolved materials
(normalized texture VFS keys); DDS done (2.5) — `docs/formats/dds.md`,
`TextureLoader` turns VFS bytes into MTLTextures with placeholder fallback;
renderer done (2.6) — `docs/rendering/metal4-renderer.md`, static-mesh path
draws `RenderScene` values (currently the synthetic `DemoScene`, which 2.7
replaces with real cell content — feed instances through
`RenderModel`/`RenderScene` + a `TextureProvider` over VFS). 2.7 + 2.8
unblocked (2.8: fly around any scene, even untextured). Winding decision was
corrected by 2.6 observation — re-verify against vanilla NIFs at 2.7
(coordinates.md). One branch/PR per numbered item. Every format item: cite
spec, synthetic in-code test fixtures, write/grow `docs/formats/<name>.md`,
verify against real install via throwaway probes (never committed).

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

Goal: roam the Tamriel exterior worldspace seamlessly — terrain under every object, cells
stream in/out around the camera, distant LOD past the loaded grid, sky + water, interiors
reachable through doors. Item ordering + sub-tasks re-checked against what M2 actually
built before starting (2.9). One branch/PR per numbered item; format items follow the same
spec/fixture/doc discipline as M2.

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
      and return. No crash on any vanilla cell touched; >30 fps sustained (frame stats,
      not eyeballed).
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
* [ ] Test probe harness: repeatable `make`-driven way to run read-only checks against the
      local install (env-gated, skipped when data absent) instead of throwaway probes.

## Open questions

* String encoding in BSA/ESM: windows-1252 vs UTF-8 (mods vary). Current: cp1252 in BSA.
  Decide lenient decode strategy engine-wide.
* Plugin load order source: hardcode vanilla masters first; `plugins.txt` support later?
