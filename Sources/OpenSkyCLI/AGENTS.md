# AGENTS.md — OpenSkyCLI

CLI dev tool target. It builds the `openskycli` binary. Full tool reference, including data-root
resolution order and exit codes: `docs/tools/cli.md`.

## What it is

Terminal probes over the engine against a real install: `vfs ls|cat`, `record`, `cell`,
`nif`, `dds`, `screenshot --out [--zoom]` (`render` alias), `bench` (sustained-fps gate).
It runs the same engine code the app runs, so a CLI failure reproduces the renderer's
behavior. `game ...` is different: it drives the running app over its agent control
socket. Load the `driving-the-running-game` skill before using it.

## Build + verify

- `make build-cli` — build (Debug). `make probe` — env-gated smoke run (`tools/probe.sh`,
  self-skips when install absent, logs -> `.logs/probe.log`).
- No CLI-only test bundle; shared logic is tested in `Tests/OpenSkyTests/`.

## Rules

- One file per subcommand (`<Name>Command.swift`). Its options are declared in the
  `OpenSkyCLIArguments` module with swift-argument-parser
  (`docs/decisions/swift-argument-parser.md`); `CommandRunners.swift` runs each parsed
  command. User-facing failures -> throw `CLIError`; `CLIError.usage` exits 2.
- CLI files only parse args + print. Reusable logic -> the package module of its domain,
  unit-tested there.
- Output is plain text, stable enough for `tools/probe.sh` to grep. Output format
  change -> update probe same commit.
- New/changed subcommand -> same commit updates `docs/tools/cli.md`, probe coverage, its
  declaration and help text in `OpenSkyCLIArguments`, and a parse test in
  `OpenSkyCLIArgumentsTests` when it adds a name scripts use.
- Install is read-only. Writes go only where `--out` points; logs -> `.logs/`.
