---
name: developing-cli-commands
description: Adds or changes an openskycli command or option - where the declaration, the
  runner, and the logic go, the option conventions the tests enforce, the companion edits
  each command needs in the same commit (docs row, probe run, parse test), and how to
  verify. Use when adding, renaming, or changing a command, subcommand, option, flag, or
  help text of openskycli, including openskycli game and openskycli reference.
---

# Developing CLI commands

`openskycli` is the developer tool over the engine (`docs/tools/cli.md`). It runs the same
engine code as the app, so a CLI failure reproduces the app's behaviour. One command is
spread over three places; this skill holds the rules for all of them.

## Where each part goes

| Part | Place |
| --- | --- |
| Arguments: names, options, flags, help, `validate()` | `Sources/OpenSkyCLIArguments/`, one struct per command, swift-argument-parser |
| Runner: the `CLIRunnable` extension that calls the command | `Sources/OpenSkyCLI/CommandRunners.swift` |
| Command: parse results in, print out | `Sources/OpenSkyCLI/Commands/<Name>Command.swift` |
| Logic worth a test | The package module of its domain, unit-tested there; the command only parses and prints |
| An app command for `game` | `AgentCommandCatalog` in `OpenSkyAgentControl`; the CLI reads it |

A new top-level command starts with `make new-cli-command NAME=<name> GROUP=<help group>`.
It writes every stub, each marked TODO, and `make cli-conventions` fails until none is left.
A new subcommand copies a sibling, such as `ReferenceArguments+Bridge.swift`.

## Option rules

`CLIConventionTests` and `make cli-conventions` enforce these, and CI fails on a miss.

- Every `@Option` takes `parsing: .unconditional`, so a value may start with `-`
  (`--y -2`).
- Help is a sentence on every command, option, flag, and argument.
- Names are lowercase kebab case, spelled out: no short options, no aliases, no old names.
- A choice is an enum from `ArgumentValues.swift`, so the help lists the values and a bad
  value exits 2. Map it to the engine type in the command, as `ReferenceCommand` maps
  `GraphicsPresetName`.
- A number is typed (`Int`, `Float`, ...) and range-checked in `validate()`, before any game
  data loads. A list is one comma-separated value. A switch is a flag, `--x` or `--no-x`.
- A group only holds subcommands; a mode is a subcommand, never a positional word.
- User-facing failures throw `CLIError`; `CLIError.usage` exits 2.
- The install is read-only. A command writes only where `--out` points, and logs go to
  `.logs/`.

## The same commit also changes

1. The row in `docs/tools/cli.md` for the command, with every option. The skill
   `driving-the-running-game` and `docs/tools/reference-game.md` list `game` and
   `reference` commands too; update them when you change one.
2. A run in `tools/probe.sh`, or one line in `tools/lint/cli-probe-exceptions.txt` saying
   why the probe cannot run it, such as "it needs a running reference game".
3. A parse test in `Tests/OpenSkyCLIArgumentsTests/` when the change adds a name scripts use.
4. The probe's expected text when an output format changes, because the probe greps it.

## Verify

1. `make build-cli` (background shell).
2. `make test-unit T=OpenSkyCLIArgumentsTests` runs the convention and parse tests. It is
   the only CLI test target; there is no `OpenSkyCLITests`.
3. `make check`, which includes `make cli-conventions`.
4. Run the command once against the install, or against the running app or reference game
   for `game` and `reference`. Close any game you started. `make probe` runs every probe
   command and skips when the install is absent.
