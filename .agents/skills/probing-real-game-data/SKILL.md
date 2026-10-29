---
name: probing-real-game-data
description: Runs engine code against the real Skyrim SE install to check a parser or
  renderer hypothesis - growing openskycli into the probe instead of throwaway code,
  offscreen render verification, and what lands in the commit. Use before writing ad-hoc
  Swift scripts, scratch test classes, or any one-off probe.
---

# Probing real game data

Sanctioned path for "run engine code against the real install and look at the result".
A probe is not throwaway code. It lands in `openskycli`, so the next session, the user, and
`tools/probe.sh` can run the same check again. A throwaway probe is lost after one session, and
the next agent writes it again from nothing.

Two things this skill deliberately does not repeat: how to write a test in this repo
(`Tests/OpenSkyTests/AGENTS.md` and `Tests/OpenSkyRealDataTests/AGENTS.md` load automatically when you
touch those directories, and cover `@MainActor`, env gating, `make test-real`, and fixtures),
and the CLI subcommand reference (`docs/tools/cli.md`).

## Build the probe into openskycli

1. Check whether a subcommand already answers the question (`openskycli --help`). `vfs`,
   `record show`, `record find`, `cell`, `nif`, `dds`, `preview`, and `render` cover most
   lookups. `record find` searches any record type by decoded field, so
   `make run-cli ARGS="record find --type LAND --where subrecords=VTEX --count"` beats writing
   new code.
2. If one comes close, extend it with an option or a report section. For example, a new
   NIF block field goes into the `nif` output, not into a new script.
3. Otherwise add a subcommand: `make new-cli-command NAME=<name> GROUP=<help group>` writes
   every stub, and the rules are in the `developing-cli-commands` skill. The logic goes into the
   package module of its domain, with a unit test, and the command only parses and prints.
4. Run it with `make run-cli ARGS=...` and commit it with the change it checked.

Name the command after what it shows, not after the bug you chase: `nif --collision` stays
useful, `debug-whiterun-door` does not.

Every command reads the whole active load order, as the game does. A probe does the same:
open it with `ActiveLoadOrder.open(root:)` and read records through its `plugins`, never a
single `ESMFile(url:)`. A record a DLC or mod overrides is only right that way, and
`make lint` (`load-order-only`) fails on a single-file open outside the format modules.

When the check is a pass/fail assertion that should keep holding, such as pixel values
from an offscreen render, write it as a real-data test in `Tests/OpenSkyRealDataTests/`
that stays, copying the shape of `CellRenderRealDataTests.swift`. That folder is the whole
`RealData` plan, so a class there runs under `make test-real` with the data root in the
host. Never `swift path/to/script.swift` against engine sources: a script cannot import the
package modules, and it does not get the data root or the memory watchdog.

## Rendering verification

Reliable paths, in order. Captures stay in `.logs/`, because a rendered frame is game
content (root `AGENTS.md`, Legal & IP boundary).

1. To look at one record, placed reference, mesh, or cell, use
   `openskycli preview --record <id> --angles all` (or `--ref`, `--mesh`, `--cell`). It
   writes a PNG and a JSON report per angle into `.logs/preview/<UTC>/`, lists unresolved
   assets, and exits 1 on a blank view. `--cell <id>` next to `--record` stands the record
   in that cell with its lighting (`docs/tools/preview-render.md`).
2. `Renderer.renderOffscreen` from a real-data test — deterministic pixel assertions
   first, with an optional local temp capture for human review (`RendererOffscreenTests`).
3. `make run-cli ARGS="render --out .logs/<run dir>/frame.png ..."` for a cell view
   with streaming, effects, or the UI overlay.
4. Ask the user to look at the running app; they see launched apps.

Output belongs to one run, not to `.logs/` at large: allocate a run directory with
`tools/run-dir.sh <name>` (or write into the one a script already printed, such as
`.logs/probe/latest`) and link that directory from the pull request, so a reviewer cannot
mistake an older capture for this run's. `make prune` ages those directories out. The
convention is `docs/tools/run-output.md`.

Screenshot and UI-test automation are not usable on every machine; check
`docs/tools/environment.md` before reaching for them.

## When the test host hangs

A real-data test host that hangs at 0% CPU before running is a known environment failure,
not a bug in your probe (`docs/tools/environment.md`). Do not keep killing and retrying it:
move that one check into `openskycli` and drive it with `make run-cli`. That promotes the CLI
above step 1 for that check only — the ranked list above still governs everything else.

## What lands in the commit

- The new or extended `openskycli` command, with `docs/tools/cli.md` and the other updates
  the `developing-cli-commands` skill lists, or the real-data test that stays.
- The finding itself, in `docs/formats/<name>.md` or a comment at the parse site.
- Never the probe output: captures and reports stay in `.logs/`. Check `git status` before
  committing.
