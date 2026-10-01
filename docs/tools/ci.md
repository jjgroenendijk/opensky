---
type: Tool
title: Continuous integration
description: What the GitHub Actions workflow runs on Linux and on macOS, how each job shares its
  make target with the git hooks, where the tool versions are pinned, why SwiftFormat runs on
  macOS, and why the Metal format check can run on Linux.
tags: [tool, ci, lint, github-actions]
---

# Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on every push to `main`. It has two
parts:

- **Lint jobs.** The checks that only read files. All but SwiftFormat run on `ubuntu-latest`.
  The `Lint` job passes only when all of them pass. It is the one required status check on
  `main`, so a pull request with a lint failure cannot merge.
- **The macOS job** (`Build & test`). It builds the app and runs the unit and UI tests. It runs
  only on manual dispatch, because a full Xcode build takes much longer than the lint jobs.

## One job per check

Each lint job runs one `make` target, the same target the git hooks and `make check` run. So
the rules live in one place, the `Makefile` and the scripts under `tools/`. The workflow only
installs the tools and calls `make`.

| Job | Make target |
| --- | --- |
| SwiftFormat | `swift-format-check` |
| SwiftLint | `swift-lint` |
| Metal format | `metal-format-check` |
| Markdown | `md-lint` |
| Shell and workflows | `sh-lint`, `workflow-lint` |
| Module graph | `module-graph` |
| Repository rules | `cli-boundary`, `realdata-plan`, `no-game-content`, `docs-links`, `docs-length`, `agent-files` |

The jobs run in parallel, so the slowest one sets the total time. The checks in "Repository
rules" each take under a second, so they share one job.

A new check gets a `make` target, a pre-commit hook, and a job, or a line in an existing job, in
the same commit. A new job also goes into the `needs` list of the `Lint` job. Branch protection
names only `Lint`, so it does not change.

## Tool versions

The workflow `env` block pins every tool version. Local tools are always the latest Homebrew
version, installed through `make bootstrap`. When Homebrew moves a tool to a new version, change
the pin to match it, or the two can disagree on a file. For example, SwiftFormat 0.63.0 wants
`///` above a function declared inside another function, and 0.63.1 wants `//`.

The jobs download release binaries or container images. They do not run `brew install`:

- SwiftFormat: the macOS release binary, on `macos-latest`.
- actionlint: the Linux release binary.
- shellcheck: the Linux release binary. It shares a job with actionlint, because actionlint
  also runs shellcheck on each `run:` script.
- SwiftLint: the official image `ghcr.io/realm/swiftlint`. It carries the SourceKit libraries
  that some rules need. The job passes `SWIFTLINT="docker run ..."` to `make`, so the flags
  stay in the `Makefile`.
- markdownlint-cli2: `npm install`, with the npm cache kept between runs.
- clang-format: the PyPI wheel, through `pipx`.
- Swift, for `swift package dump-package`: the toolchain in the runner image.

## SwiftFormat on macOS

The Linux SwiftFormat binary checks one file in under a second. On the whole tree it took 2 to 3.5
minutes, so its parallel workers slow each other down. SwiftFormat stops a rule after
a fixed time: 1 second plus 1 millisecond per token, and no option changes it. So on Linux the
`docComments` rule timed out on random files, and the job failed with no finding. Preloading
jemalloc did not help. On a macOS runner the same check takes about 30 seconds.

Standard hosted runners, macOS included, cost nothing in a public repository.

## Metal format on Linux

The `Makefile` calls `xcrun clang-format` for the shaders. Linux has no `xcrun`, so the job
passes `CLANG_FORMAT=clang-format` and installs upstream clang-format 21.1.8.

Apple clang-format 21 (clang-2100) and upstream 21.1.8 gave byte-identical output on
`Shaders.metal` after its indentation and spacing were scrambled. If a later Xcode changes the
output, the Metal format job and the local hook disagree. Then move the pin to the upstream
version that matches, or run the job on macOS.

## Not in CI

- `swift-baseline`. It checks for the Apple toolchain on purpose.
- Anything that needs an Xcode build, except the manual macOS job.
- The real-data suites. A runner has no game install.
