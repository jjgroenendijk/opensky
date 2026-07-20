---
type: Task List
title: Roadmap and outstanding work
description: OpenSky mission roadmap - agent handoff, milestone plan, open questions.
tags: [meta, roadmap, planning, handoff]
timestamp: 2026-07-20T00:00:00Z
---

# TODO — roadmap

State as of 2026-07-20. Ordered by mission priority (AGENTS.md): render static world
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
(bootstrap handles the download). CI is suspended (Actions quota) — git hooks are the
only gate; `ci.yml` is manual-dispatch and self-skips below Xcode 26.

## Milestones at a glance

Each milestone = one goal, one measurable acceptance gate (its last numbered item). Done
milestone leaves this file; history lives in `docs/log.md` + git.

* M1 — data foundation. Done 2026-07-10 (PRs #1-#8): BSA VFS, ESM/plugin record decoders.
* M2 — static world geometry. Done 2026-07-18 (PRs #9-#21): textured
  `WhiterunExterior06` on screen, free-fly camera, bench-gated fps (avg 0.39 ms/frame @
  720p on M1, Debug), `openskycli` + main-app asset browser dev tools.
* M3 — world streaming + environment. Done 2026-07-19 (PRs #22-#35): streamed 5x5
  exterior grid, terrain, textured distant LOD incl. 32-bit terrain/object diffuse atlases,
  sky/water, lit interiors + door round trips.
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

* [ ] Re-enable CI when GH Actions quota returns: restore `pull_request` + `push`
      triggers in `.github/workflows/ci.yml`, re-add "Format & lint" + "Build & test"
      required status checks on main, drop the suspension notes in AGENTS.md +
      commit skill. Until then git hooks are the only gate (never `--no-verify`).
* [ ] Decide `.metal` formatter/linter (clang-format?) — AGENTS.md wants both for every
      language; document exception if none fits.
* [ ] Commit-msg hook checks subject only; body sections enforced by review.

## Open questions

* String encoding in BSA/ESM: windows-1252 vs UTF-8 (mods vary). Current: cp1252 in BSA.
  Decide lenient decode strategy engine-wide.
* Plugin load order source: hardcode vanilla masters first; `plugins.txt` support later?
