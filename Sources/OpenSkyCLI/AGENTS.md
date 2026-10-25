# AGENTS.md — OpenSkyCLI

CLI dev tool target. It builds the `openskycli` binary. Full tool reference, including data-root
resolution order and exit codes: `docs/tools/cli.md`.

## What it is

Terminal probes over the engine against a real install, such as `record show`, `record find`,
`cell`, `nif`, and `render --out`. `openskycli --help` lists them by group. It runs the same
engine code the app runs, so a CLI failure reproduces the renderer's behavior. `game ...` is
different: it drives the running app over its agent control socket. Load the
`driving-the-running-game` skill before using it.

## Build + verify

- `make build-cli` — build (Debug). `make probe` — env-gated smoke run (`tools/probe.sh`,
  self-skips when install absent, logs -> `.logs/probe.log`).
- No CLI-only test bundle; shared logic is tested in `Tests/OpenSkyTests/`.

## Rules

- One file per command (`<Name>Command.swift`). Its options are declared in the
  `OpenSkyCLIArguments` module with swift-argument-parser
  (`docs/decisions/swift-argument-parser.md`); `CommandRunners.swift` runs each parsed
  command. User-facing failures -> throw `CLIError`; `CLIError.usage` exits 2.
- Start a new command with `make new-cli-command NAME=<name> GROUP=<help group>`. It writes
  the declaration, the runner, the command file, the docs row, and the probe run as TODO
  stubs.
- Follow the conventions in `docs/tools/cli.md#conventions`: one name, no aliases, a mode is
  a subcommand, a choice is an enum, a number is typed and range-checked in `validate()`.
  `CLIConventionTests` and `make cli-conventions` check them.
- CLI files only parse args + print. Reusable logic -> the package module of its domain,
  unit-tested there.
- Output is plain text, stable enough for `tools/probe.sh` to grep. Output format
  change -> update probe same commit.
- New/changed command -> same commit updates `docs/tools/cli.md`, the probe run (or a reason
  in `tools/lint/cli-probe-exceptions.txt`), its help text, and a parse test in
  `OpenSkyCLIArgumentsTests` when it adds a name scripts use.
- An app command for `game` is declared once in `AgentCommandCatalog`, in
  `OpenSkyAgentControl`; the CLI parses, refuses, and prints help from it.
- Install is read-only. Writes go only where `--out` points; logs -> `.logs/`.
