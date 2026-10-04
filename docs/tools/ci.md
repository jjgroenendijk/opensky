---
type: Tool
title: Continuous integration
description: What the GitHub Actions workflow runs on macOS, how each step shares its make target
  with `make check`, how the jobs fit the macOS runner limit, how the caches and Renovate
  work, and why the build-and-test job runs no real-data test.
tags: [tool, ci, lint, github-actions]
---

# Continuous integration

`.github/workflows/ci.yml` runs on every pull request that is ready for review and on every push to
`main`. Every check
runs on an `xcode-27` runner (macOS 27), so CI uses the same platform, Xcode, and tools as a
developer machine. `Changes` and `Lint` only read results, so they run on Linux.

| Job | Make targets |
| --- | --- |
| Format | `swift-format-check`, `metal-format-check`, `md-lint` |
| Static checks | `swift-lint`, `sh-lint`, `workflow-lint`, `module-graph`, `cli-boundary`, `realdata-plan`, `lint-test-plans`, `lint-test-tags`, `lint-test-targets`, `no-game-content`, `docs-links`, `docs-length`, `agent-files`, `comment-length`, `duplicates`, `no-suppressions` |
| Changes | None. It decides whether Build & test runs |
| Build & test | `swift-baseline`, `ffmpeg`, `test-unit`, `coverage-floor` |
| Lint | None. It passes only when the jobs above pass |

`Lint` is the one required status check on `main`. A pull request with a lint failure or a
failing unit test cannot merge. A new job goes into the `needs` list of `Lint`, so branch
protection does not change.

A draft pull request runs no job. The work on an issue goes to a draft pull request, one commit at
a time, so a draft would otherwise use macOS runners for unfinished work. `gh pr ready` sends the
`ready_for_review` event, and that starts the full run. Each later push to a ready pull request runs
CI again.

A pull request that changes only Markdown, `docs/`, `.AGENTS/`, `.claude/`, or the Renovate config
skips Build & test, because nothing in it is compiled. `Lint` accepts that skip only when
`Changes` asked for it. A push to `main` always builds, so the compilation cache stays current.

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
version, installed through `make bootstrap`. The pins must follow, or the two can disagree on a
file. For example, SwiftFormat 0.63.0 wants
`///` above a function declared inside another function, and 0.63.1 wants `//`.

The jobs download the macOS release binaries of SwiftFormat, SwiftLint, shellcheck, and
actionlint, and cache them by version. They do not run `brew install`, because Homebrew installs
only its newest version, not the pin. markdownlint-cli2 and jscpd come from `npm`. clang-format
for the shaders is Xcode's, through `xcrun`, the same as locally.

actionlint also runs shellcheck on each `run:` script, so the two share a job and a pin.

## Dependency updates

Renovate (`.github/renovate.json`) opens one pull request each Monday with every update. CI runs on
it like on any other pull request. It runs only after the Renovate GitHub app is installed on the
repository.

- **GitHub Actions and Swift packages**, through Renovate's built-in managers.
- **The tool pins in the workflow `env`.** A `# renovate:` comment above each pin names its release
  source. After a pin moves, `brew upgrade` brings the local tool to the same release.
- **Not updated:** `DEVELOPER_DIR`, which follows the local Xcode, and ffmpeg.
  `tools/vendor-ffmpeg.sh` pins the tarball checksum next to the version, and Renovate cannot check
  a new checksum against Homebrew's, as that script requires.

## Build & test

The job builds the app, the CLI, and every test bundle, and runs the `UnitTests` plan. It uses
ad hoc signing (`CODE_SIGN_IDENTITY=-`), because a runner has no signing identity.

- **No game data.** A runner has no Skyrim install. The job sets no `OPENSKY_DATA_ROOT`, so a
  test gated on the install skips. The real-data suites only compile: the `OpenSky` scheme builds
  `OpenSkyRealDataTests` for testing, so the unit build compiles it in the same `xcodebuild` call.
  `make realdata-plan` checks that every such suite lives in `OpenSkyRealDataTests`, which the
  unit plan does not include.
- **Metal 4.** A test that needs a Metal 4 GPU gates on `device.supportsFamily(.metal4)` and
  skips without one. The runner's virtual GPU has no Metal 4, so these tests run only on a
  developer machine.
- **Xcode.** The image holds several Xcodes, and its default changes over time. So the workflow
  `env` sets `DEVELOPER_DIR` to the one Xcode that matches the local one, and
  `make swift-baseline` fails when the two Swift versions differ
  ([Swift toolchain](/tools/swift-toolchain.md)). The `xcode-27` image is a public preview of
  GitHub, so a job can wait longer for a runner than on `macos-26`.
- **Every error at once.** The job sets Xcode's "continue building after errors" default, so a
  failed run lists the compile errors of every target.
- **CI-only build flags.** `BUILD_FLAGS` turns off the index store, which nothing in CI reads, and
  skips the package plugin and macro trust prompts. They change no compiler output, so CI still
  builds what `make test-unit` builds locally.
- **Metal Toolchain.** `tools/ci/metal-toolchain.sh start` downloads it in the background while
  the caches restore, and `wait` joins it before the build. It is not cached: it is 1.5 GB on disk,
  so a restore takes as long as the download and uses space the compilation cache needs.
- **Timing.** `tools/ci/build-timing.sh` writes the build and test time, the compilation cache hit
  rate, the time per task kind, and the slowest tasks to the run summary. It reads the build log in
  the result bundle, because `xcodebuild test` ignores `-showBuildTimingSummary`. The job uploads
  `logs/` on every run, not only on failure.

## Caches

A repository keeps 10 GB of caches. When it is full, GitHub drops the least recently used entry.

| Cache | Key | Saved by |
| --- | --- | --- |
| Vendored ffmpeg | hash of `tools/vendor-ffmpeg.sh` | any run that missed it |
| SDK modules (`ModuleCache.noindex`, `SDKStatCaches.noindex`) | Xcode build version | a push to `main` that missed it |
| Compilation cache (`CompilationCache.noindex`) | `cas-<arch>-<scope>-<run>`, where scope is `main` or `pr-<number>` | every run that was not cancelled |

The compilation cache roughly halves the build:

- A pull request restores its own newest entry first, then falls back to `main`'s. So the second
  push to a pull request reuses the first push's work.
- After each save, `tools/ci/cache-prune.sh` deletes the older entries of the same scope.
- The `Cache cleanup` workflow deletes a pull request's entries when it closes.
- The cache is saved after a failed test too, because the compiled tasks are still valid.
- A restored store only grows. `COMPILATION_CACHE_LIMIT_SIZE` does not shrink it
  ([build system](/tools/build-system.md)). So a push to `main` deletes the store before the build
  when it is over `CAS_MAX_MB`. That run builds cold and saves a fresh, small entry.

## Not in CI

- `make test-ui`. It needs the Accessibility grant, which a runner cannot give.
- `make test-sanitize` and the real-data perf gates.
- The real-data suites. A runner has no game install.
