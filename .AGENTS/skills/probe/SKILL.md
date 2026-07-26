---
name: probe
description: Run engine code against the real Skyrim SE install to check a
  parser/renderer hypothesis - where to probe from, offscreen render verification,
  the 0%-CPU hang workaround. Use before writing ad-hoc swift scripts or throwaway
  test classes.
---

# Probing real game data

Sanctioned path for "run engine code against the real install and look at the
result". Probes are throwaway and never land in commits.

Two things this skill deliberately does not repeat: how to write a test in this
repo (`openskyTests/AGENTS.md` loads automatically when you touch that directory,
and covers `@MainActor`, env gating, `make realtest`, and fixtures), and the CLI
subcommand reference (`docs/tools/cli.md`).

## Prefer openskycli when it already covers the question

`vfs ls|cat`, `record`, `cell`, `nif`, `dds`, `render`, `bench` cover most lookups:
`make run-cli ARGS="record --type LAND ..."` beats writing a probe. A probe that
recurs across sessions gets promoted to an `openskycli` subcommand (rules in
`openskycli/AGENTS.md`).

Otherwise, probe from a scratch test class in `openskyTests/`, copying the shape of
`CellRenderRealDataTests.swift`. Never `swift path/to/script.swift` against engine
sources — the engine is not a package, so a script cannot import `opensky` and dies
on top-level statement rules.

## Rendering verification

Screen Recording TCC is missing on this machine and UI-test automation is flaky.
Reliable paths, in order. Captures are temporary or `logs/`-local; a rendered frame
embeds the user's game assets, so it is never committed.

1. `Renderer.renderOffscreen` from a unit test — deterministic pixel assertions
   first, with an optional local temp capture for human review
   (`RendererOffscreenTests`).
2. `make run-cli ARGS="render --out logs/frame.png ..."`.
3. Ask the user to look at the running app; they see launched apps.

If a real-data XCTest host hangs at 0% CPU before running (a known flake on this
machine — see `docs/testing.md`), do not keep killing and retrying it: move the
one-off check into `openskycli` and drive it with `make run-cli`. The CLI is the
first-choice real-data probe surface here, not a fallback. UI tests blocking on
"enabling automation mode" is the same TCC class — run `make test-perms` once.

## Cleanup

Before commit: scratch test files deleted, `git status` clean of probe artifacts.
A probe finding worth keeping goes to `docs/formats/<name>.md` or a code comment at
the parse site, not the probe itself.
