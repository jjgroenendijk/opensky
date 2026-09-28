---
type: Tool
title: Test runs
description: How test runs are put together - the four checked-in test plans and the deadlock that
  keeps UI tests apart, the fast loop over cached products, the RealData plan, code coverage,
  sanitizers, and where test time goes.
tags: [testing, tooling, xcodebuild]
---

# Test runs

This page explains how the commands on the [testing setup](/testing.md) page run. The xcodebuild
behaviors they depend on, with the dates they were seen, are on the
[environment](/tools/environment.md) page.

## Test plans

Which bundles a run touches is a checked-in test plan, not a flag. The `opensky` scheme has four,
under `Config/`:

| Plan | Test targets | Used by |
| --- | --- | --- |
| `UnitTests.xctestplan` | `openskyTests` | `make test`, `make test-fast`, `make test-one`. The scheme default |
| `UITests.xctestplan` | `openskyUITests` | `make test-ui` |
| `RealData.xctestplan` | `openskyRealDataTests`, plus the data root | `make realtest`, `make realtest-all` |
| `Sanitizers.xctestplan` | `openskyTests`, one configuration per sanitizer | `make test-sanitize` |

`xcodebuild` builds every buildable in a scheme's Test action before it looks at `-only-testing`, so
a selector never saves building a bundle. A plan does, because the plan decides what is built.
`make test-one` adds `-only-testing` on top of a plan, and switches to `UITests` when the selector
names `openskyUITests`.

No plan lists the UI bundle beside an app-hosted bundle, and this is on purpose. `openskyTests` and
`openskyRealDataTests` are hosted by `opensky.app`. Put either in the same session as the UI runner,
and xcodebuild starts the app as a test host with `libXCTestBundleInject.dylib`. The app then waits
in `-[XCTestDriver _prepareTestConfigurationAndIDESession]` for an IDE session that belongs to the
runner, while the runner waits for the app to enter automation mode. Neither moves, and after 60
seconds XCTest reports `Timed out while enabling automation mode`. The message names a permission,
which sent several searches looking for a missing grant, but it is a deadlock.
`-only-testing:openskyUITests` does not avoid it, because a selector filters tests, not the targets
the session starts. Only the plan does.

## The fast loop

A warm `make test` or `make realtest` spends most of its time on the build system starting,
resolving the scheme and plan, and checking the whole graph, not on the tests. A warm single
real-data run took about 85 seconds, of which the tests took about 5.

`tools/test-fast.sh` splits the two halves. `xcodebuild build-for-testing` compiles and writes one
`.xctestrun` per plan. `xcodebuild test-without-building -xctestrun` then runs with no build system
at all. The `.xctestrun` is rebuilt only when an input is newer than it: sources, `Config/` (the
RealData root is in there), the project file, or `.vendor/ffmpeg`. That check takes a fraction of a
second, where even a build-for-testing with nothing to do takes tens of seconds. `B=1` forces the
rebuild.

A plan's environment entry lands in the `.xctestrun` as written, so the data root needs no
injection, and the script reads the root back from the file it is about to run.

Two rules carry over from the real-data script. The memory watchdog wraps every RealData run. The
result bundle count is checked after every run, because a selector that matches nothing runs zero
tests and exits 0 under `test-without-building` too. `make realtest-all` and `make realtest-perf`
stay on `tools/realtest.sh`: the whole set rebuilds rarely, and an optimized build cannot live in the
cached `.xctestrun`.

## The RealData plan

`Config/RealData.xctestplan` holds a literal install path. A plan value is not macro-expanded, so
`$(OPENSKY_DATA_ROOT)` would arrive as those characters, and this entry is the one place the root is
set. `tools/realtest.sh` reads it back and refuses to run when a different `OPENSKY_DATA_ROOT` is
exported, instead of testing an install the plan does not name. To use another install, edit the
plan.

A plan's `selectedTests` does not match Swift Testing tests: selecting any runs zero tests. So the
plan selects the whole target, which does work. That is why the real-data suites are their own
bundle. Before, they lived in `openskyTests`: every unit build compiled them though they always
skipped there, and the plan needed a long hand-kept list of suites. The shared fixtures now compile
into both bundles instead. Types that mixed a fixture with `@Test` methods were split into a fixture
in `openskyTestSupport/` and tests in an extension under `openskyTests/`, so no test name changed.

`make realdata-plan`, part of `make lint`, checks that every suite with a `dataRoot: GameDataRoot?`
and a `@Test` is in `openskyRealDataTests/`, that the plan selects that target and nothing narrows
it, and that no plan lists an app-hosted bundle beside `openskyUITests`.

## Code coverage

The unit, UI, and sanitizer plans gather line coverage for the `opensky` target only, so the number
is about engine code, not the test bundles. `make test` gathers it and `make test-report` prints it.
There is no separate target and no `-enableCodeCoverage` flag. `ENABLE_CODE_COVERAGE` defaults to
`YES` in Xcode, so coverage was already gathered on every run and thrown away. Scoping it cost
nothing measurable: turning it on explicitly recompiled nothing and changed the time within noise.

There is no coverage threshold and no coverage number in CI. The value is finding defensive branches
in the parsers that no test takes, the malformed-input paths behind "malformed input must not
crash". A floor would need a baseline argument, like a perf budget.

## Sanitizers

`make test-sanitize` runs `openskyTests` under runtime sanitizers. Three things make this worth the
time: ffmpeg is reached across a C boundary where Swift's safety stops, the parsers slice
`UnsafeRawBufferPointer` over memory-mapped archives, where a bad read lands in mapped memory instead
of failing a bounds check, and much of the engine's concurrency is in `nonisolated` code that Swift
6 does not check statically.

| Configuration | Plan options | Products |
| --- | --- | --- |
| `Thread` | `threadSanitizerEnabled` | `DerivedData/Build/Products/Variant-TSan/` |
| `Address` | `addressSanitizer.enabled`, `undefinedBehaviorSanitizerEnabled` | `.../Variant-ASan-UBSan/` |

The two sanitizers cannot share a build. xcodebuild builds every configuration in a plan even when
told to run one, so `SAN=Thread` narrows what runs, not what compiles. That is why this is its own
plan: as configurations on `UnitTests`, the sanitized builds would compile on every `make test`. The
first run of each configuration recompiles everything, so it is an occasional check, like
`make realtest-all`. A sanitizer report shows as a failing test. Both configurations were clean when
added, so a new report is a regression, and a real one becomes its own GitHub issue.

## Where test time goes

Building costs more than testing. Cross-module incremental builds are on, so the test bundle
recompiles only files that use a changed declaration. But the whole engine is one module that every
test file imports, so a change to a widely used type still recompiles most of both targets. An edit
inside one function body recompiles one file. Adding one internal method recompiled about 80 app
files and 16 test files. The shared compilation cache removes the cold first build in a new worktree
([build system](/tools/build-system.md#one-store-for-every-worktree)).

Swift Testing reports a duration that includes time a `@MainActor` test waited for the main actor.
So durations from a parallel run are not a cost profile. Measure one test with
`-parallel-testing-enabled NO`.
