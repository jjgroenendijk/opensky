---
name: probing-real-game-data
description: Runs engine code against the real Skyrim SE install to check a parser or
  renderer hypothesis - where to probe from, offscreen render verification, and cleanup
  before commit. Use before writing ad-hoc Swift scripts or throwaway test classes.
---

# Probing real game data

Sanctioned path for "run engine code against the real install and look at the result". A
probe is throwaway and never lands in a commit.

Two things this skill deliberately does not repeat: how to write a test in this repo
(`openskyTests/AGENTS.md` and `openskyRealDataTests/AGENTS.md` load automatically when you
touch those directories, and cover `@MainActor`, env gating, `make realtest`, and fixtures),
and the CLI subcommand reference (`docs/tools/cli.md`).

## Prefer openskycli when it already covers the question

`vfs ls|cat`, `record`, `cell`, `nif`, `dds`, `render`, `bench` cover most lookups:
`make run-cli ARGS="record --type LAND ..."` beats writing a probe. A probe that recurs
across sessions gets promoted to an `openskycli` subcommand (rules in `openskycli/AGENTS.md`).

Otherwise probe from a scratch test class in `openskyRealDataTests/`, copying the shape of
`CellRenderRealDataTests.swift`. That folder is the whole `RealData` plan, so a class there
runs under `make realtest` with the data root in the host. Never
`swift path/to/script.swift` against engine sources — the engine is not a package, so a
script cannot import `opensky` and dies on top-level statement rules.

## Rendering verification

Reliable paths, in order. Captures are temporary or `logs/`-local; a rendered frame embeds
the user's game assets, so it is never committed.

1. `Renderer.renderOffscreen` from a scratch test class — deterministic pixel assertions
   first, with an optional local temp capture for human review (`RendererOffscreenTests`).
2. `make run-cli ARGS="render --out logs/<run dir>/frame.png ..."`.
3. Ask the user to look at the running app; they see launched apps.

Output belongs to one run, not to `logs/` at large: allocate a run directory with
`tools/run-dir.sh <name>` (or write into the one a script already printed, such as
`logs/probe/latest`) and link that directory from the pull request, so a reviewer cannot
mistake an older capture for this run's. `make prune` ages those directories out. The
convention is `docs/tools/run-output.md`.

Screenshot and UI-test automation are not usable on every machine; check
`docs/tools/environment.md` before reaching for them.

## When the test host hangs

A real-data XCTest host that hangs at 0% CPU before running is a known environment failure,
not a bug in your probe (`docs/tools/environment.md`). Do not keep killing and retrying it:
move that one check into `openskycli` and drive it with `make run-cli`. That promotes the CLI
above step 1 for that check only — the ranked list above still governs everything else.

## Cleanup

Before commit: scratch test classes deleted, `git status` clean of probe artifacts. A probe
finding worth keeping goes to `docs/formats/<name>.md` or a code comment at the parse site,
not the probe itself.
