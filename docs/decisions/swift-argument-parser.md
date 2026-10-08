---
type: Decision
title: swift-argument-parser for the openskycli command line
description: Why openskycli declares its commands with Apple's swift-argument-parser, where the
  declarations live, and how the CLI keeps its old names and exit codes.
tags: [decision, dependency, swiftpm, cli]
---

# swift-argument-parser for the openskycli command line

## Decision

- `openskycli` declares its commands, options, and help with
  [swift-argument-parser](https://github.com/apple/swift-argument-parser) from Apple. Its
  license is Apache 2.0, which allows redistributing OpenSky's code with it.
- The declarations live in the `OpenSkyCLIArguments` module. It has its own product, and only
  the `openskycli` target links it. The app and the engine modules do not import it.
- The tracked `Package.resolved` pins the version, as for
  [swift-collections](/decisions/swift-collections.md).

## Why

The CLI has more than 25 commands. Each one read its options by hand, and a usage text of about
300 lines was kept in sync by hand. The parser gives:

- typed options and arguments, checked before a command runs;
- help generated from the declarations: `openskycli --help` and `openskycli help <command>`;
- one help page for each command and subcommand.

## Why a separate module

The CLI target uses main-actor default isolation. The parser's property wrappers do not build
there: a `nonisolated` command type fails with "'nonisolated' cannot be applied to mutable
stored properties", and a main-actor one cannot conform to `ParsableCommand`. So the
declarations sit in a package module with the nonisolated default. The CLI target conforms each
parsed command to its own `CLIRunnable` protocol and runs it on the main actor.

## Compatibility with the old scanner

The old scanner took the next word as an option's value, whatever it was. Every option uses
`parsing: .unconditional` to keep this, so `--y -2` stays a value. `--data-root` is accepted
before and after the command name. The parser's usage exit code is 64; the CLI maps it to 2, as
before. `game` has a hidden default subcommand that collects every word it does not know, so
`game input press jump --frames 3` reaches the app unchanged.

## Alternatives

- Keep the scanner. It worked, but its help text drifted from the real options, and every
  command repeated the same parse and check code.
- Declare the commands in the CLI target. This does not build, see above.
