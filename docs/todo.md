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

Sequencing: 3.1 terrain first — everything sits on it, and LAND lives in the same cell
temporary-children groups `CellSceneBuilder` already walks
(`docs/engine/cell-scene.md`) -> decoder slots into the existing walk. 3.2 streaming
turns that per-cell unit into a grid + carries the perf work multi-cell rendering needs.
3.3 LOD needs the grid boundary (rings start where loaded cells end). 3.4 sky/water +
3.5 interiors independent of 3.2/3.3 -> parallelizable branches; 3.6 lighting last
(interiors are where it shows). Verification path: `openskycli render`/`bench` +
`openskypreview`, screenshot pattern as in `docs/img/`. Watch item: 3.4 sky turns the
black background in screenshots into a real frame.

Format facts below pre-verified 2026-07-18 against UESP mod-file-format pages + xEdit
`dev-4.1.6` source (`wbDefinitionsTES5.pas`, `wbDefinitionsCommon.pas`, `wbLOD.pas`) +
DynDOLOD docs / xLODGen LODGen source. Re-confirm against real install by probe during
impl; chase flagged UNCONFIRMED points especially.

### 3.1 Terrain

* [ ] Terrain render: splat pipeline — base + ATXT layers per quadrant blended by VTXT
      alpha (format allows 8 + base; live engine limit community-reported ~6 — probe
      vanilla max), decide texture binding strategy (array vs per-quadrant draws),
      record in rendering doc.
* [ ] Verify: `openskycli render` of target cell + 8 neighbors — terrain under the M2
      walls, no seams at cell borders; screenshot.

### 3.2 Cell streaming

* [ ] Grid manager: camera position -> cell coords -> desired 5x5 grid (uGridsToLoad
      default), diff -> load/unload sets, hysteresis so border crossing does not thrash.
* [ ] Async build: cell build off main queue (concurrency audit of `CellSceneBuilder` +
      `MeshLibrary`/`TextureLibrary` sharing), scene handoff on main, per-frame
      integration budget. Launch path goes async too — no startup block (2.7 note).
* [ ] Scene structure: per-cell scene units composing one multi-cell draw pass; unload
      drops instances, libraries stay shared (eviction deferred — measure memory first).
* [ ] Perf for many cells: instanced draws (2.7 grouping is instancing-ready), frustum
      culling vs per-model world AABBs.
* [ ] Widen base coverage so the streamed world is not sparse: MSTT/TREE/FURN/ACTI/CONT
      bases drawn as static models (skip taxonomy shrinks; animation/interaction stay
      out of M3).
* [ ] Verify: scripted camera-path bench (extend `openskycli bench` with a fly-path
      across cells) — hitch budget during loads, memory plateaus, no crash.

### 3.3 Distant LOD

* [ ] `lodsettings/<worldspace>.lod` parse: 16 B = SW origin cell (int16 x2), stride,
      min/max LOD level. Ref: UESP "LOD Settings File Format" + xEdit `wbLOD.pas`.
      Doc: `docs/formats/lod.md` (covers all of 3.3).
* [ ] Terrain LOD: `meshes/terrain/<ws>/<ws>.<level>.<x>.<y>.btr` — NIF container
      (existing parser) + new blocks BSMultiBoundNode/BSMultiBound/BSMultiBoundAABB;
      level N covers NxN cells, name coords = SW cell, grid anchored at lodsettings
      origin; textures `textures/terrain/<ws>/<ws>.<level>.<x>.<y>.dds` + `_n`. Water
      LOD shapes (node "WATER") skipped until 3.4 lands.
* [ ] Object LOD: `.../objects/<ws>.<level>.<x>.<y>.bto` — BSSubIndexTriShape (new
      block), vanilla atlas `textures/terrain/<ws>/objects/<ws>.objects.dds`; levels
      4/8/16. Caveat: .btr/.bto layout derived from xLODGen generator source, not a
      Bethesda spec -> defensive parse + probe sweep over every vanilla Tamriel
      .btr/.bto before trusting.
* [ ] Ring selection: level-4 blocks outside the loaded 5x5, coarser levels farther,
      hide blocks under loaded cells; plain distance constants first (ini
      `fBlockLevel*Distance` fidelity later). Tree LOD (.btt/.lst billboards, non-NIF,
      layout in `wbLOD.pas`) — include if cheap, else defer with a todo note.
* [ ] Verify: horizon filled past the grid from the target cell, no double-draw where
      full cells are loaded; screenshot.

### 3.4 Sky + water

* [ ] Sky: procedural dome or fullscreen gradient + sun disc, time-of-day parameter.
      Hardcoded plausible colors first; later sample default climate WTHR NAM0 entries
      (0 sky-upper, 7 sky-lower, 8 horizon — UESP WTHR/CLMT). Weather system itself out
      of M3 scope.
* [ ] Water: height from CELL XCLW (sentinel 0x7F7FFFFF = no water; CK-bug values
      0x4F7FFFC9/0xCF000000 treated same) else WRLD DNAM default (Tamriel -14000, PNAM
      parent inheritance); flat plane per cell, simple animated shader; colors
      (shallow/deep/reflection) from WATR DNAM (228/232 B SSE variants — parse only
      those fields) via CELL XCWT else WRLD NAM2. First alpha-BLEND pipeline variant
      (renderer has opaque + alpha-test only). Ref: UESP CELL/WRLD/WATR.
* [ ] Verify: screenshot with horizon sky at the target cell; water visible at a
      river/lake cell (probe picks one nearby).

### 3.5 Interiors

* [ ] Interior CELL walk: CELL top group -> block (type 2) / sub-block (type 3) by
      FormID last decimal digits (block = objectID mod 10, sub-block = div 10 mod 10;
      labels untrusted, same rule as exterior walk). Reuse `CellSceneBuilder` children
      walk; CELL DATA 0x1 = interior, no terrain/sky. Ref: UESP CELL + xEdit
      `wbImplementation.pas`.
* [ ] Doors: DOOR bases (MODL) drawn like STAT; REFR XTEL decode — 32 B = destination
      door REFR formid + pos xyz + rot xyz + flags. Ref: UESP REFR/DOOR.
* [ ] Teleport: door activation (proximity + key first, raycast later) -> resolve dest
      REFR -> load its cell (interior or exterior) -> camera at XTEL pos/rot; exterior
      streaming suspends while inside.
* [ ] Verify: enter a Whiterun-area interior through its door, look around, return to
      the exterior grid (probe picks the door pair).

### 3.6 Lighting pass

* [ ] Cell light values: XCLL (92 B layout; truncated variants exist — fields optional
      from the directional-ambient block on) + LTMP -> LGTM template (DATA + DALC),
      XCLL inherit flags pick per-field source. XCLL directional-rotation units
      UNCONFIRMED — probe. Ref: UESP CELL/LGTM.
* [ ] LIGH decoder: DATA 48 B — time, radius, color, flags (no type flag = omni point),
      falloff exponent; FNAM fade; REFR overrides XRDS radius, XEMI emit. Negative/spot
      lights skipped for now. Ref: UESP LIGH + xEdit flag list.
* [ ] Forward pass: ambient + directional from cell values, N nearest point lights per
      draw, fog from XCLL near/far/color.
* [ ] Verify: interior screenshot lit vs unlit comparison; exterior look unchanged
      (sun/sky driven).

### 3.7 Milestone acceptance

* [ ] Free-fly from the M2 target cell across the streamed grid under sky: terrain +
      objects stream without visible pop-in gaps, water renders where cells have it,
      LOD beyond the grid, enter one interior through a door and return. No crash on
      any vanilla cell touched; >30 fps sustained measured via `openskycli bench` (not
      eyeballed).
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
