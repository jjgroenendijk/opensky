---
type: Tool
title: Continuous integration
description: What the GitHub Actions workflow runs on macOS, how each step shares its make target
  with `make check`, how the jobs fit the macOS runner limit, how the caches and Renovate
  work, and why the build-and-test job runs no real-data test.
tags: [tool, ci, lint, github-actions]
---

# Continuous integration

`.github/workflows/ci.yml` runs on every push to a pull request, draft or not, and on every push
to `main`. Marking a draft ready starts no run: the run of its last push tested the same commit,
and a second run took 7 to 17 minutes with no new result. Every check
runs on an `xcode-27` runner (macOS 27), so CI uses the same platform, Xcode, and tools as a
developer machine. `Changes` and `Lint` only read results, so they run on Linux.

| Job | Make targets |
| --- | --- |
| Format | `format-check`: every `tools/format/` script with `--check` |
| Static checks | `lint`: every `tools/lint/` script and its self-check |
| Changes | None. It decides whether Build & test runs |
| Index checks | `lint-index` |
| Build & test | `test PLAN=UnitTests COVERAGE=1`: the whole unit plan, the coverage floors, and the changed lines (diffed against the base on a pull request) |
| Lint | None. It passes only when the jobs above pass |

`Lint` is the one required status check on `main`. A pull request with a lint failure or a
failing unit test cannot merge. A new job goes into the `needs` list of `Lint`, so branch
protection does not change.

A draft pull request runs every job, on every push. The work on an issue goes to a draft pull
request one commit at a time, and the runner tests each commit while the session goes on with the
next one, so the session never runs the whole unit plan locally. A newer push cancels the run of
the older one, so unfinished work costs at most one run per push.

A pull request that changes only Markdown, `docs/`, `.agents/`, `.claude/`, the Python tools in
`tools/wiki-mirror/`, the markdownlint config in `tools/markdown/`, or the Renovate config skips
Build & test, because nothing in it is compiled. Static checks still lint and test those files. `Lint`
accepts that skip only when `Changes` asked for it. A push to `main` always builds, so the
compilation cache stays current.

## The same gate as make check

Format and Static checks run `make format-check` and `make lint`, the two halves of `make check`, so
the gate is the same locally and in CI by construction. The workflow only installs the tools and
calls `make`. Each part runs to its end even when another part fails, so one run shows every
finding.

A new check is a new script in `tools/lint/` or `tools/format/` and needs no workflow edit.

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
  test gated on the install skips. The real-data suites only compile, in the `Index checks` job:
  a build of the unit plan does not compile `OpenSkyRealDataTests`. `tools/lint/realdata-plan.sh` checks
  that every such suite lives in `OpenSkyRealDataTests`, which the unit plan does not include.
- **Metal 4.** A test that needs a Metal 4 GPU gates on `device.supportsFamily(.metal4)` and
  skips without one. The runner's virtual GPU has no Metal 4, so these tests run only on a
  developer machine.
- **Xcode.** The image holds several Xcodes, and its default changes over time. So the workflow
  `env` sets `DEVELOPER_DIR` to the one Xcode that matches the local one, and
  `tools/lint/swift-baseline.sh` fails when the two Swift versions differ
  ([Swift toolchain](/tools/swift-toolchain.md)). The `xcode-27` image is a public preview of
  GitHub, so a job can wait longer for a runner than on `macos-26`.
- **Every error at once.** The job sets Xcode's "continue building after errors" default, so a
  failed run lists the compile errors of every target.
- **CI-only build flags.** `BUILD_FLAGS` turns off the index store, which nothing in CI reads, and
  skips the package plugin and macro trust prompts. They change no compiler output, so CI still
  builds what `make test` builds locally.
- **Metal Toolchain.** `tools/ci/metal-toolchain.sh start` downloads it in the background while
  the caches restore, and `wait` joins it before the build. It is not cached: it is 1.5 GB on disk,
  so a restore takes as long as the download and uses space the compilation cache needs.
- **Timing.** `tools/ci/build-timing.sh` writes the build and test time, the compilation cache hit
  rate, the time per task kind, and the slowest tasks to the run summary and the job log. It reads
  the build log in the result bundle, because `xcodebuild test` ignores `-showBuildTimingSummary`,
  and keeps a copy in `.logs/build-timing/`. The job uploads `.logs/` on every run, not only on
  failure, so `gh run download <run> -n build-test-logs` gets the start time and duration of every
  build task.

## Index checks

`make lint-index` runs every check that reads the index store: Periphery's unused-code scan and the
adapter rule (`tools/lint-index/adapter-references.py`). A task replayed from the compilation cache
writes almost no index data. Measured 2026-11-08: a Debug build of the CLI into an empty tree,
served from a warm cache, wrote 276 index units for about 5,000 Swift files. So the index build
cannot reuse the cached build of Build & test. It builds uncached on its own runner, at the same
time as Build & test. It also builds `OpenSkyRealDataTests`, which no other job compiles.

Measured 2026-11-08 on #1885: the job takes 17 to 19 minutes, of which `make lint-index` is about 16.
Build & test takes 22 minutes with a cold compilation cache and 10.5 with a warm one. On the
development Mac the same uncached build takes about 9 minutes.

So the job builds incrementally. A push to `main` saves its whole index tree, and every run
restores the newest one before it builds:

1. The restored tree holds `source-commit`, the commit it was built from.
2. A checkout gives every file the current time, so the build would compile all of it.
   `tools/ci/source-times.sh` therefore sets every tracked file to one fixed old time, then gives
   the current time only to the files that differ from `source-commit`.
3. The build then compiles the changed files and the files that depend on them.

The tree is 4.4 GB on disk and about 1.1 GB compressed (measured 2026-11-09), so only a push to
`main` saves it, and `tools/ci/cache-prune.sh` deletes the older trees after each save.

## Caches

A repository keeps 10 GB of caches. When it is full, GitHub drops the least recently used entry.

| Cache | Key | Saved by |
| --- | --- | --- |
| Vendored ffmpeg | hash of `tools/vendor-ffmpeg.sh` | any run that missed it |
| SDK modules (`ModuleCache.noindex`, `SDKStatCaches.noindex`) | Xcode build version | a push to `main` that missed it |
| Compilation cache (`CompilationCache.noindex`) | `cas2-<arch>-<scope>-<run>`, where scope is `main` or `pr-<number>` | every run that was not cancelled |
| Index tree (`DerivedData-index`, SDK modules) | `index1-<arch>-<Xcode build>-<commit>` | every push to `main` |

The compilation cache roughly halves the build:

- A pull request restores its own newest entry first, then falls back to `main`'s. So the second
  push to a pull request reuses the first push's work.
- A pull request run builds the pull request merged into the current `main`. When `main` changed
  a low-level module since the last run, most tasks miss even though the pull request did not
  change. That is a real source change, not a broken cache: the same sources hit 601 of 601.
- After each save, `tools/ci/cache-prune.sh` deletes the older entries of the same scope.
- Only `main` and open pull requests can restore an entry. The `Cache cleanup` workflow deletes
  every other entry when a pull request closes and once a day. The daily sweep is needed because
  a run can still be building when its pull request merges. Such a run saves nothing and skips
  the build if it has not started yet, but a save a few seconds before the merge still leaks.
  On 2026-10-17, ten leaked entries held 8.7 GB of the 10 GB, and GitHub evicted live entries.
- The cache is saved after a failed test too, because the compiled tasks are still valid.
- A restored store only grows. `COMPILATION_CACHE_LIMIT_SIZE` does not shrink it
  ([build system](/tools/build-system.md)). So a push to `main` deletes the store before the build
  when it is over `CAS_MAX_MB`. That run builds cold and saves a fresh entry.
- One cold build makes a store of about 1.9 GB on disk (measured 2026-10-17). Each push to
  `main` adds 0.4 to 0.8 GB, and a 2.8 GB store is 890 MB compressed. `CAS_MAX_MB` is 5120, so
  about every fifth push to `main` builds cold. At 3072 it was every third. A limit below one cold
  build would delete the store on every push to `main`. Every build on `main` would then be cold.

## Weekly

`weekly.yml` runs on Sunday night and on demand (`gh workflow run weekly.yml`). It holds only
`make test PLAN=Sanitizers SAN=thread` and `SAN=address`. Each rebuilds everything with instrumentation,
which costs too much on every pull request.

The `Module metrics` job runs `make module-metrics` and keeps `module-metrics.md` as a run
artifact for 90 days. It is design rule 6 of [Design metrics](/decisions/design-metrics.md), a
report that fails nothing.

The `Design groups` job runs `make design-groups` and keeps `design-groups.txt` as a run
artifact for 90 days. It is design rule 7 of [Design metrics](/decisions/design-metrics.md), a
report that fails nothing. It builds the index store first, so it takes as long as a build.

No pull request fails on a weekly finding, so the `Report` job keeps one issue,
"Weekly checks fail on main", with the `bug` and `code-health` labels
(`tools/ci/weekly-issue.sh`). A failed run opens it, or comments on it when it is open. A green
run closes it. To test the step, `gh workflow run weekly.yml --ref <branch> -f force_failure=true`
fails the checks at once and opens the issue.

## Preview releases

`preview.yml` builds the Release app and publishes it as a GitHub pre-release every night and on
demand. It reads the `Lint` result of `ci.yml` to pick a commit, and it restores the caches that
`ci.yml` saves without saving its own. [Releases](/tools/releases.md) explains it.

## Not in CI

- `make test PLAN=UITests`. It needs the Accessibility grant, which a runner cannot give.
- The real-data suites and perf gates. A runner has no game install.
