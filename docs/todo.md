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
* M3 — world streaming + environment (active): roam exterior worldspace seamlessly —
  terrain, cell streaming, distant LOD, sky/water, interiors via doors. Gate: 3.8.
* M4 — toward playable (direction only): collision, animation, scripting, audio, UI.
  Re-scope after M3; no gate yet.

## Milestone 3 — world streaming + environment

Goal: roam the Tamriel exterior worldspace seamlessly — terrain under every object, cells
stream in/out around the camera, distant LOD past the loaded grid, sky + water, interiors
reachable through doors. One branch/PR per numbered item; format items follow the same
spec/fixture/doc discipline as M2 (cite spec, synthetic in-code fixtures,
`docs/formats/<name>.md`, verify via repeatable `openskycli` probes).

Sequencing: 3.1 terrain landed first — everything sits on it, and LAND lived in the same
cell temporary-children groups `CellSceneBuilder` already walked
(`docs/engine/cell-scene.md`) -> decoder slotted into the existing walk. 3.2 streaming now
turns that per-cell unit into a grid + carries the perf work multi-cell rendering needs.
LOD rings now start at loaded-grid boundary. 3.6 interiors follows; 3.7 lighting lands
last because interiors are where it shows. Verification path: `openskycli render`/`bench`
plus main-app asset
browser, screenshot pattern as in `docs/img/`.

Format facts below pre-verified 2026-07-18 against UESP mod-file-format pages + xEdit
`dev-4.1.6` source (`wbDefinitionsTES5.pas`, `wbDefinitionsCommon.pas`, `wbLOD.pas`) +
DynDOLOD docs / xLODGen LODGen source. Re-confirm against real install by probe during
impl; chase flagged UNCONFIRMED points especially.

### 3.6 Interiors

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

### 3.7 Lighting pass

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

### 3.8 Milestone acceptance

* [ ] Free-fly from the M2 target cell across the streamed grid under sky: terrain +
      objects stream without visible pop-in gaps, water renders where cells have it,
      LOD beyond the grid, enter one interior through a door and return. No crash on
      any vanilla cell touched; >30 fps sustained measured via `openskycli bench` (not
      eyeballed).
* [ ] Screenshot under `docs/`; `docs/log.md` + this file updated; M4 re-scoped into
      numbered items with a gate.

## Milestone 4+ — toward playable (far out)

Direction only — re-scope into numbered gated items at 3.8. Candidate order:

* Collision + character controller (walk on terrain first; HKX collision reversing later).
* Animation: HKX (Havok) reversing — hardest format; consider skeleton-only first.
* Papyrus VM: PEX bytecode interpreter (open docs exist), event dispatch.
* Audio: .fuz (lip + xwm), xwm via AVFoundation/ffmpeg-free route to be researched.
* UI: game HUD/menus are Scaleform SWF — likely custom native UI instead; decide.
* LOD quality: decode tree `.btt`/`.lst` billboards; clip boundary BTR triangles/segments
  so 4x4 block anchoring leaves no conservative gap; read `fBlockLevel*Distance` INI values.

## Tooling / meta

* [ ] Decide `.metal` formatter/linter (clang-format?) — AGENTS.md wants both for every
      language; document exception if none fits.
* [ ] Commit-msg hook checks subject only; body sections enforced by review.

## Open questions

* String encoding in BSA/ESM: windows-1252 vs UTF-8 (mods vary). Current: cp1252 in BSA.
  Decide lenient decode strategy engine-wide.
* Plugin load order source: hardcode vanilla masters first; `plugins.txt` support later?
