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
* M5 — actors on screen. Done 2026-07-20 (PRs #52-#59): bind-pose clothed actors stream
  with cells in Whiterun exterior + interiors, reason-tagged exact accounting, actor-enabled
  fly bench within build/footprint/frame budgets.
* M6 — actors animate (active): skeleton-driven idle playback on streamed actors.
  Gate: 6.6.
* M7+ — toward playable (direction only): Papyrus VM, audio, UI.

## Milestone 6 — actors animate (idle playback)

Goal: streamed actors leave bind pose — race idle animation plays on placed actors. No
AI/behavior graphs (no `behaviors/*.hkx` evaluation); direct clip playback only. One
branch/PR per numbered item; format items follow `format-parser` discipline.

Format caveat: Havok HKX has no official public spec. Leads: community tooling notes
(hkxcmd, ck-cmd), Bethesda modding wiki hkx pages, NifTools skeleton discussions. All
byte layouts + version tags below unverified from-memory leads — confirm against real
headers by probe at impl, flag deviations.

* [ ] 6.1 HKX container parse: SSE 64-bit Havok packfile — header, version string
      (expected hk_2010.2.0-r1; verify on real files), section table, class-name
      table, object data offsets. Gate: `openskycli` dumps section + class inventory
      for `skeleton.hkx` and one idle `.hkx` from the install; synthetic fixture tests
      cover header/section/class-table parsing + malformed input.
* [ ] 6.2 hkaSkeleton decode: bone names, parent indices, reference pose; name-map onto
      the NIF skeleton nodes bind-pose skinning already uses. Gate: real human
      `skeleton.hkx` hierarchy maps onto `skeleton.nif` body bones with mismatches
      reason-tagged; synthetic hierarchy tests.
* [ ] 6.3 Idle clip decode: hkaAnimation track data for one idle clip
      (spline-compressed animation expected — probe + document actual class), output
      per-bone local-transform samples. Gate: real idle clip decodes to bounded,
      NaN-free transforms over full duration; synthetic decode tests.
* [ ] 6.4 Pose sampling + palette update: sample clip at frame time -> compose world
      bone matrices -> refresh skinning palette each frame, replacing the static bind
      palette. Gate: offscreen frames at two clip times differ for an animated actor,
      identical for a static prop; palette math unit-tested.
* [ ] 6.5 Streamed playback lifecycle: resident-cell actors play their race idle,
      clip state builds/evicts with the cell; actor accounting stays exact +
      reason-tagged. Gate: actor-enabled fly bench passes with animation on, explicit
      added per-frame animation budget.
* [ ] 6.6 Milestone acceptance: Whiterun exterior + one interior animate without crash
      across the streamed grid; frame-delta evidence + screenshot under `docs/img/`
      linked from docs; `docs/log.md` + this file updated; M7 re-scoped into numbered
      items with a gate.

## Milestone 7+ — toward playable (far out)

Direction only — re-scope after M6. Candidate order:

* Papyrus VM: PEX bytecode interpreter (open docs exist), event dispatch.
* Audio: .fuz (lip + xwm), xwm via AVFoundation/ffmpeg-free route to be researched.
* UI: game HUD/menus are Scaleform SWF — likely custom native UI instead; decide.

## Backlog (unscheduled, keep filed)

* LOD quality: tree `.btt`/`.lst` billboards; read `fBlockLevel*Distance` INI values.
* GMST-driven movement constants (walk/run speed, step height) replacing 4.1 hardcodes.
* Creature skinning variant: `SabreCat.nif` `NiSkinPartition` carries a vertex bone
  palette index the flattener rejects ("vertex bone palette index out of range") ->
  reason-tagged actor failure (ACHR `000DC8DE`, M5.6 run). Decode the variant per
  nif.xml; natural fit alongside M6 skeleton work.

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
