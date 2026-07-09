---
type: Task List
title: Roadmap and outstanding work
description: OpenSky mission roadmap - current state, next steps, open questions.
tags: [meta, roadmap, planning]
timestamp: 2026-07-09T00:00:00Z
---

# TODO — roadmap

State as of 2026-07-09. Ordered by mission priority (AGENTS.md): render static world
geometry first -> grow toward playable engine.

## Done

* Dev tooling: Makefile hub, git hooks, SwiftFormat/SwiftLint/markdownlint/shellcheck,
  CI. `make check` green.
* Xcode project: native macOS-only (was iOS template), project format Xcode 26.3
  (objectVersion 100), programmatic AppKit app, shared scheme, ad-hoc signing.
* Metal 4 skeleton: MTL4CommandQueue/CommandBuffer/ArgumentTable/ResidencySet pipeline,
  rotating triangle renders on M1 (visually confirmed 2026-07-09). MatrixMath unit-tested.
* Metal Toolchain download wired into `tools/bootstrap.sh` (Xcode 26 ships without it).

## Milestone 1 — read game data

* [ ] Game data locator: probe default Steam path + configurable override
      (`~/Library/Application Support/Steam/...`; this machine:
      `/Volumes/data/steam/steamapps/common/Skyrim Special Edition/`).
      Fail loud when missing. Never bundle data.
* [x] BSA v105 (SSE) archive parser: header, folder/file records, LZ4
      decompression, lazy reads. Ref: UESP BSA format page. Documented in
      `docs/formats/bsa.md`. Name-hash computation deferred (lookups keyed
      by name tables; vanilla always ships them).
* [ ] ESM/ESP record scaffolding: TES4 header, group/record/subrecord walk,
      lazy field parse. Ref: UESP Mod File Format + xEdit definitions.
      Doc in `docs/formats/esm.md`.

## Milestone 2 — static world geometry

* [ ] NIF mesh parser (subset: BSTriShape geometry) via NifTools `nif.xml` ref.
* [ ] DDS texture loader (BC1/BC3/BC7 -> MTLTexture).
* [ ] Load one exterior cell's static refs (STAT records) -> draw with Metal 4.
* [ ] Camera: free-fly WASD + mouse look.

## Milestone 3+ (later)

* Terrain (LAND records), water, sky. Interior cells. LOD (BTO/BTR).
* Animation (HKX) — far out; needs Havok-format reversing.
* Papyrus VM (PEX) — far out.

## Tooling / meta

* [ ] CI: `macos-latest` runner needs Metal Toolchain for shader compile —
      add `xcodebuild -downloadComponent MetalToolchain` step or gate build job.
* [ ] Decide `.metal` formatter/linter (clang-format?) — AGENTS.md wants both for
      every language; document exception if none fits.
* [ ] Commit-msg hook checks subject only; body sections enforced by review.

## Open questions

* Coordinate conventions: Skyrim is Z-up, right-handed, units ~1.428 cm; Metal
  clip z [0,1]. Decide engine-internal convention before NIF work; doc decision.
* String encoding in BSA/ESM: windows-1252 vs UTF-8 (mods vary). Decide lenient
  decode strategy.
