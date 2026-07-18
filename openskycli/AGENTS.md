# AGENTS.md — openskycli

CLI dev tool target. Root `/AGENTS.md` is the contract; this file adds CLI-specific
rules. Full tool reference: `docs/tools/cli.md`.

## What it is

Terminal probes over the engine against a real install: `vfs ls|cat`, `record`, `cell`,
`nif`, `dds`, `render --out [--zoom]`, `bench` (sustained-fps gate). Runs the same
engine code the app runs — a CLI failure reproduces the renderer's behavior.
Data root resolution: `--data-root` flag ->
`OPENSKY_DATA_ROOT` env -> `OpenSkyDataRoot` user default -> Steam path. Exit codes:
0 ok, 1 failure, 2 usage.

## Build + verify

- `make cli` — build (Debug). `make probe` — env-gated smoke run (`tools/probe.sh`,
  self-skips when install absent, logs -> `logs/probe.log`).
- No CLI-only test bundle; shared logic is tested in `openskyTests/`.

## Rules

- One file per subcommand (`<Name>Command.swift`). Args parsed with stdlib
  `ArgumentScanner` — no swift-argument-parser (decision in `docs/tools/cli.md`).
  User-facing failures -> throw `CLIError`.
- CLI files only parse args + print. Reusable logic -> `opensky/` shared engine tree,
  unit-tested there.
- Output is plain text, stable enough for `tools/probe.sh` to grep. Output format
  change -> update probe same commit.
- New/changed subcommand -> same commit updates `docs/tools/cli.md`, probe coverage,
  and usage text in `OpenSkyCLI.swift`.
- Install is read-only. Writes go only where `--out` points; logs -> `logs/`.
