# AGENTS.md — OpenSkyCLI

CLI dev tool target. It builds the `openskycli` binary. Full tool reference, including data-root
resolution order and exit codes: `docs/tools/cli.md`.

## What it is

Terminal probes over the engine against a real install, such as `record show`, `record find`,
`cell`, `nif`, and `render --out`. `openskycli --help` lists them by group. It runs the same
engine code the app runs, so a CLI failure reproduces the renderer's behavior. `game ...` is
different: it drives the running app over its agent control socket. Load the
`driving-the-running-game` skill before using it.

## Rules

- Load the `developing-cli-commands` skill before adding or changing a command or option.
  It holds the conventions the tests enforce and the edits each command needs.
- CLI files only parse args + print. Reusable logic -> the package module of its domain,
  unit-tested there.
- Install is read-only. Writes go only where `--out` points; logs -> `.logs/`.
