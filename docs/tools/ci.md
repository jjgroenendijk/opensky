---
type: Tool
title: Continuous integration
description: What the GitHub Actions workflow runs on macOS, how each step shares its make target
  with `make check`, how the jobs fit the macOS runner limit, where the tool versions are pinned,
  and why the build-and-test job runs no real-data test.
tags: [tool, ci, lint, github-actions]
---

# Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on every push to `main`. Every job runs
on a `macos-26` runner, so CI uses the same platform, Xcode, and tools as a developer machine.

| Job | Make targets |
| --- | --- |
| Format | `swift-format-check`, `metal-format-check`, `md-lint` |
| Static checks | `swift-lint`, `sh-lint`, `workflow-lint`, `module-graph`, `cli-boundary`, `realdata-plan`, `lint-test-plans`, `lint-test-tags`, `lint-test-targets`, `no-game-content`, `docs-links`, `docs-length`, `agent-files`, `comment-length`, `duplicates`, `no-suppressions` |
| Build & test | `swift-baseline`, `ffmpeg`, `test`, `coverage-floor`, `realdata-build` |
| Lint | None. It passes only when the three jobs above pass |

`Lint` is the one required status check on `main`. A pull request with a lint failure or a
failing unit test cannot merge. A new job goes into the `needs` list of `Lint`, so branch
protection does not change.

## One make target per step

Each step runs a `make` target that `make check` or `make test-unit` also runs. So the rules live in
one place, the `Makefile` and the scripts under `tools/`. The workflow only installs the tools and
calls `make`. A step after the first one in a job runs even when an earlier step failed, so one
run shows every finding.

A new check gets a `make` target and a step in the same commit.

## The runner limit

The repository is public, so standard hosted runners cost nothing, macOS included. But the Free
plan runs at most 5 macOS jobs at the same time per account. So the lint checks share two jobs
instead of one job each. One run starts at most 3 jobs at once: Format, Static checks, and Build &
test. `Lint` starts only after they finish. Two pull requests can then run side by side without
waiting for a free runner.

## Tool versions

The workflow `env` block pins every tool version. Local tools are always the latest Homebrew
version, installed through `make bootstrap`. When Homebrew moves a tool to a new version, change
the pin to match it, or the two can disagree on a file. For example, SwiftFormat 0.63.0 wants
`///` above a function declared inside another function, and 0.63.1 wants `//`.

The jobs download the macOS release binaries of SwiftFormat, SwiftLint, shellcheck, and
actionlint, and cache them by version. They do not run `brew install`, because Homebrew installs
only its newest version, not the pin. markdownlint-cli2 and jscpd come from `npm`. clang-format
for the shaders is Xcode's, through `xcrun`, the same as locally.

actionlint also runs shellcheck on each `run:` script, so the two share a job and a pin.

## Build & test

The job builds the app, the CLI, and the unit bundles, and runs the `UnitTests` plan. It uses
ad hoc signing (`CODE_SIGN_IDENTITY=-`), because a runner has no signing identity.

- **No game data.** A runner has no Skyrim install. The job sets no `OPENSKY_DATA_ROOT`, so a
  test gated on the install skips. The real-data suites only compile (`make realdata-build`).
  `make realdata-plan` checks that every such suite lives in `OpenSkyRealDataTests`, which the
  unit plan does not include.
- **Metal 4.** A test that needs a Metal 4 GPU gates on `device.supportsFamily(.metal4)` and
  skips without one. The runner's virtual GPU has no Metal 4, so these tests run only on a
  developer machine ([environment](/tools/environment.md)).
- **Xcode 26.** The runner builds with the Xcode that `make swift-baseline` names as the floor,
  which can be older than the local one. Code must build with both.
- **Every error at once.** The job sets Xcode's "continue building after errors" default, so a
  failed run lists the compile errors of every target.
- **Cache.** The vendored ffmpeg is cached on the hash of `tools/vendor-ffmpeg.sh`. The Xcode
  compilation cache (`DerivedData/CompilationCache.noindex`) roughly halves the build. One entry
  is about 430 MB and a repository keeps 10 GB of caches, so only a push to `main` saves it,
  and a pull request restores the newest one. A restored cache only grows, so its key starts
  over each month. The Metal Toolchain download takes seconds, so it is not cached.
- **On failure** the job uploads `logs/`, which holds the full `xcodebuild` transcripts.

## Not in CI

- `make test-ui`. It needs the Accessibility grant, which a runner cannot give.
- `make test-sanitize` and the real-data perf gates.
- The real-data suites. A runner has no game install.
