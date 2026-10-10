---
type: Tool
title: Test runs
description: How test runs are put together - one plain xcodebuild call per test plan, the
  deadlock that keeps UI tests apart, tag plans, the RealData plan, code coverage, sanitizers, and
  where test time goes.
tags: [testing, tooling, xcodebuild]
---

# Test runs

This page explains how the commands on the [testing setup](/testing.md) page run. The xcodebuild
behaviors they depend on, with the dates they were seen, are on the
[environment](/tools/environment.md) page.

## Test plans

Which bundles a run touches is a checked-in test plan, not a flag. Each `make test-<kind>` target is
one plain `xcodebuild test` call on one plan, with no script between `make` and `xcodebuild`, so the
plan decides what runs. `make lint-test-targets` fails a target that runs tests under another name.
A plan builds only the bundles it lists, and the build is most of a run's time, so the plans are
small. The `OpenSky` scheme has these plans, under `config/TestPlans/`:

| Plan | Test targets | Used by |
| --- | --- | --- |
| `UnitTests.xctestplan` | `OpenSkyTests` and every package test target | `make test-unit PLAN=UnitTests`; CI on every push. The scheme default |
| `Quick.xctestplan` | every package test target, skipping the tests tagged `slow` and `gpu` | `make test-unit`, the default plan. Builds no app |
| `Formats.xctestplan` | the `OpenSkyFormats*Tests` targets | `make test-unit PLAN=Formats` |
| `Engine.xctestplan` | the engine-layer targets: game data, behavior, launch, agent control, physics, rendering, audio, world state | `make test-unit PLAN=Engine` |
| `Features.xctestplan` | the feature targets, save, menus, and preview | `make test-unit PLAN=Features` |
| `App.xctestplan` | `OpenSkyTests` | `make test-unit PLAN=App` |
| `AgentControl.xctestplan` | `OpenSkyAgentControlTests` | `make build-app`, `make build-cli` in Debug, so the app and the CLI build in the test build context |
| `GPU.xctestplan` | the unit plan's targets, only the tests tagged `gpu` | `make test-unit PLAN=GPU` |
| `UITests.xctestplan` | `OpenSkyUITests` | `make test-ui` |
| `RealData.xctestplan` | `OpenSkyRealDataTests`, only the suites tagged `smoke`, plus the data root | `make test-real` |
| `RealDataAll.xctestplan` | `OpenSkyRealDataTests`, plus the data root | `make test-real ALL=1` |
| `Perf.xctestplan` | `OpenSkyRealDataTests`, only the tests tagged `perf`, plus the data root | `make test-real PERF=1` |
| `Sanitizers.xctestplan` | the unit plan's targets, one configuration per sanitizer | `make test-sanitize SAN=thread`, `SAN=address`; the weekly CI workflow |

The four layer plans, `Formats`, `Engine`, `Features`, and `App`, partition the unit plan: each
target is in exactly one of them. The Debug `build-app` and `build-cli` targets use
`build-for-testing` on the `AgentControl` plan rather than a plain `build`, because a plain build
compiles the package modules without coverage mapping and a test build with it, and the two
contexts rewrite the same intermediates (Code coverage, below).

`make lint-test-plans`, part of `make lint`, checks the rules below that a machine can check: every
plan is in the scheme, sets the timeouts, sets no repetition, and selects no test by name. It also
checks that the Perf plan selects only the `perf` tag with the RealData data root, that the
`RealData` plan selects only the `smoke` tag and `RealDataAll` the whole target, that `Quick` skips
`slow` and `gpu`, that the layer plans partition the unit plan, and that the sanitizer and `GPU`
plans list the unit plan's targets and set its environment, such as the shader library path.

## Timeouts

Every plan sets `testTimeoutsEnabled`, `defaultTestExecutionTimeAllowance`, and
`maximumTestExecutionTimeAllowance`. A test that runs past its allowance fails with its name and
"Test exceeded execution time allowance", and the test host is stopped. Without it, a hung test
blocks `xcodebuild` until someone kills it, as the `AVAudioPlayerNode.playerTime` hang did
([environment](/tools/environment.md)). This works for Swift Testing tests, both a test blocked on a
thread and one awaiting forever. Other tests in the same host stop with it and are not named.

An allowance has a minimum of 60 seconds. Each value sits well above the slowest test of the plan,
measured serially with `-parallel-testing-enabled NO`:

| Plan | Slowest test | Default | Maximum |
| --- | --- | --- | --- |
| `UnitTests` | 10 s | 120 s | 300 s |
| `UITests` | not measured | 300 s | 600 s |
| `RealData`, `Perf` | 152 s | 600 s | 1800 s |
| `Sanitizers` | 25 s | 600 s | 1800 s |

A parallel run reports a test's time including its wait for the main actor, up to 20 s for a unit
test that alone takes milliseconds, so the unit allowance leaves room for that. A test that fails on
its allowance is a hang to find, not a limit to raise.

## Tags

Swift Testing tags label suites and tests: `.gpu`, `.slow`, `.acceptance`, `.perf`, and `.parser`,
from `Tests/OpenSkyTagsTesting/Tags.swift`. `Tests/AGENTS.md` says which suite carries which, and
`make lint-test-tags` checks the ones a machine can find.

A plan's `selectedTests` matches no Swift Testing test, but its `selectedTags` does. Each test
target entry takes `"selectedTags" : { "tags" : [ "perf" ] }`. The Perf plan ran exactly the two
tagged tests of `OpenSkyRealDataTests` this way. xcodebuild has no flag that selects a tag, so a tag
run needs its own plan: `GPU` is the unit plan with every target narrowed to one tag, and `Quick`
is the package targets with two tags skipped.

A tag cannot replace a plan. A plan chooses the bundles that are built and the environment of the
host; a tag only chooses tests inside them. So the real-data suites stay in their own bundle.

`make test-report` prints passed, failed, and time per tag. A result bundle does not carry the tags,
so the report reads them from the sources and matches each test by suite and name.

## Repeat runs and reruns

`make test-unit T='Suite/test()' N=100` passes `-run-tests-until-failure -test-iterations N` and
stops at the first failure. It is a make target and not a plan configuration on purpose. A plan with
`testRepetitionMode` would repeat every run that uses the plan, and a retry on failure hides the
failure a flaky hunt is looking for. `make lint-test-plans` fails a plan that sets either.

`make test-rerun PLAN=<plan>` runs `xcodebuild test-without-building` on the `.xctestrun` file
that the last `xcodebuild test` or `build-for-testing` of that plan wrote under `Build/Products/`.
It skips the build system, so one suite reruns in seconds instead of the start-up cost below. It
tests the products as they were built: the target warns when a source under `Sources/` or `Tests/`
is newer than the file, and the warning means the result is for the old code.

`make test-package T='Target/Suite'` runs `swift test --filter` for one package test target. It
needs no Xcode and no app. SwiftPM links every package test target into one bundle, so the first
run compiles them all, under the build lock; later runs recompile only what changed. It shares
the `swift build` products of `make compile`.

## Attachments

A green unit run writes a result bundle with no attachments at all, so the plans leave
`userAttachmentLifetime` and `systemAttachmentLifetime` at their defaults: deleting attachments on
success would save nothing. The unit plans set `diagnosticCollectionPolicy` to `Never`. With the
default, xcodebuild collected a system log archive after the last bundle finished, 60 MB of a
106 MB bundle and about 9 s of a 37 s test phase on 2026-10-05, on a green run too. The test
output, the failures, and the per-test durations stay in the bundle.

`xcodebuild` builds every buildable in a scheme's Test action before it looks at `-only-testing`, so
a selector never saves building a bundle. A plan does, because the plan decides what is built.
`T=...` adds `-only-testing` on top of the target's plan. A misspelled Swift Testing selector runs
zero tests and still exits 0, so check the count in the output.

No plan lists the UI bundle beside an app-hosted bundle, and this is on purpose. All three unit
bundles are hosted by `OpenSky.app`. Put either in the same session as the UI runner,
and xcodebuild starts the app as a test host with `libXCTestBundleInject.dylib`. The app then waits
in `-[XCTestDriver _prepareTestConfigurationAndIDESession]` for an IDE session that belongs to the
runner, while the runner waits for the app to enter automation mode. Neither moves, and after 60
seconds XCTest reports `Timed out while enabling automation mode`. The message names a permission,
which sent several searches looking for a missing grant, but it is a deadlock.
`-only-testing:OpenSkyUITests` does not avoid it, because a selector filters tests, not the targets
the session starts. Only the plan does.

## Start-up cost

A warm `xcodebuild test` spends about as long before the first test as on the tests. Every run
prints a `phases` line and keeps `phases.tsv` in its run directory
([build system](/tools/build-system.md#phases)). Measured on 2026-10-05 with the cache on the
internal disk, the lock held, and nothing edited:

| Run | start | resolve | plan | build | test | total |
| --- | --- | --- | --- | --- | --- | --- |
| `PLAN=UnitTests`, after a `Quick` run | 2 s | 1 s | 6 s | 2 s | 31 s | 43 s |
| `PLAN=Quick`, after a `UnitTests` run | 1 s | 1 s | 6 s | 2 s | 26 s | 38 s |
| `PLAN=Formats`, after a `UnitTests` run | 1 s | 1 s | 5 s | | 3 s | |

`start` is xcodebuild scanning the package folder and loading the scheme and the manifest
before it resolves the graph; it grows with every visible file under the repository root, and
was 9 to 30 s while a link to the compilation cache store sat there
([the start-up scan](/tools/build-system.md#the-workspace-and-the-start-up-scan)). A change of
plan builds nothing, because the scheme builds the app-hosted bundle in every plan
([environment](/tools/environment.md#a-compilation-cache-hit-leaves-the-driver-record-dirty)).
Over three weeks of runs before the cache moved, the median whole-plan run took 7.5 minutes: the
difference was waiting on the external disk and on other sessions' builds. Each run pays the
start-up, so batch edits into one run, and rerun a built plan with `make test-rerun`.

### The test phase

The `Quick` plan runs 30 bundles on 6 test runners at once, in plan order, 133 s of runner time
in a 26 s span; the session logs in the result bundle (`xcresulttool export diagnostics`) hold
the timestamps. Launching a runner and loading its bundle costs 1 to 3 s per bundle, 68 s of the
133 s, so merging small bundles into fewer hosts is the next lever. Eight runners changed
nothing, and the longest bundles first saved 2 to 3 s: the span is set by the longest chains,
`OpenSkyPhysicsTests` at 17 s and `OpenSkyWorldTests` at 9 s. `UnitTests` adds `OpenSkyTests`,
26 s in the app.

`make test-real` and `make test-sanitize` start `tools/memguard.sh` beside the
call and turn parallel testing off, so one test host runs and the watchdog's cap is per run. `CAP=MB`
changes the cap.

`make test-real` runs the `RealData` plan, which selects the `smoke` tag: one quick suite per
format family and subsystem, so a change gets a real-data check in minutes. `ALL=1` runs
`RealDataAll`, the whole bundle, for a milestone acceptance.

## The RealData plan

`config/TestPlans/RealData.xctestplan` holds a literal install path. A plan value is not
macro-expanded, so `$(OPENSKY_DATA_ROOT)` would arrive as those characters. The `RealDataAll` and
Perf plans hold the same path, and `make lint-test-plans` fails when they differ. An exported
`OPENSKY_DATA_ROOT` does not change it. To use another install, edit all three plans.

A plan's `selectedTests` does not match Swift Testing tests: selecting any runs zero tests. So the
plans select the whole target, or a tag, which do work. That is why the real-data suites are their
own bundle. The shared fixtures compile into both bundles.

`make realdata-plan`, part of `make lint`, checks that every suite with a `@Test` that reads
`RealDataEnvironment` or declares a `dataRoot: GameDataRoot?` is in `Tests/OpenSkyRealDataTests/`,
that the plan selects that target and nothing narrows it, and that no plan lists an app-hosted
bundle beside `OpenSkyUITests`.

## Code coverage

The unit, UI, and sanitizer plans gather line coverage for the `OpenSky` target and the package
modules only, so the number is about engine code, not the test bundles. `make test-unit COVERAGE=1`
passes `-enableCodeCoverage YES` and gathers it, and `make test-report` prints it. A local run
passes `NO`, because gathering and merging the profile adds time to every run and the number is
read only by `make coverage-floor`, which CI runs on every push with `COVERAGE=1`.

The plan's target list scopes only the report. A test build compiles every target with
`-profile-coverage-mapping -profile-generate`, test bundles and fixtures included. A plain `build`
compiles without them, and both write the same package intermediates under `Build/`.
Without a fix, `make build-cli` after `make test-unit` would recompile the whole engine, and the
next test build would do it again. The `Makefile` therefore passes `CLANG_COVERAGE_MAPPING=YES`
on every Debug command line (`COVERAGE_Debug`), and `tools/probe.sh` does the same. It has to be
the command line: xcodebuild sets this setting per action above `config/Build/Overrides.xcconfig`,
so an xcconfig value does not reach the compiler. A Release build stays without coverage. An
instrumented program writes `default.profraw` into its working directory when it exits;
`.gitignore` covers it.

`make test-report` and `make coverage-floor` read `Build/ProfileData/*/Coverage.profdata`
with `llvm-cov`, not the result bundle with `xccov`. Each package module builds into its own
framework under `PackageFrameworks/`, and the bundle lists none of them as a coverage product. So
`xccov` reports only the app, with no files, and a plan's package targets change nothing. Each test
run rewrites that profile, so read it right after `make test-unit`. A filtered run covers less and
reads too low.

`make coverage-floor` fails when an `OpenSkyFormats*` module is under the floor, `COVERAGE_FLOOR` in
the `Makefile`. CI runs it after the unit tests.
Only the parsers have a floor: they read untrusted files, and the value is finding defensive
branches that no test takes, the malformed-input paths behind "malformed input must not crash"
([code-health automation](/decisions/code-health-automation.md)).

## Sanitizers

`make test-sanitize SAN=thread` and `SAN=address` run the unit bundles under runtime
sanitizers. Three things make this worth the
time: ffmpeg is reached across a C boundary where Swift's safety stops, the parsers slice
`UnsafeRawBufferPointer` over memory-mapped archives, where a bad read lands in mapped memory instead
of failing a bounds check, and much of the engine's concurrency is in `nonisolated` code that Swift
6 does not check statically.

| Configuration | Plan options | Products |
| --- | --- | --- |
| `Thread` | `threadSanitizerEnabled` | `Build/Products/Variant-TSan/` |
| `Address` | `addressSanitizer.enabled`, `undefinedBehaviorSanitizerEnabled` | `.../Variant-ASan-UBSan/` |

The two sanitizers cannot share a build. xcodebuild builds every configuration in a plan even when
told to run one, so each target narrows what runs, not what compiles. That is why this is its own
plan: as configurations on `UnitTests`, the sanitized builds would compile on every `make
test-unit`. The first run of each configuration recompiles everything, so the weekly CI workflow
runs both, not a local session. A sanitizer report shows as a failing test. Both configurations were
clean when added, so a new report is a regression, and a real one becomes its own GitHub issue.

## Where test time goes

Building costs more than testing. Cross-module incremental builds are on, so a test bundle
recompiles only files that use a changed declaration. Inside one module, most test files use most
of it, so a change to a widely used engine type still recompiles most of `OpenSkyTests`. The parser
tests are in their own bundle over their own module, so an engine change does not recompile them
([Swift modules](/tools/modules.md)). An edit inside one function body recompiles one file. The
shared compilation cache removes the cold first build in a new worktree ([build system](/tools/build-system.md#one-store-for-every-worktree)).

Swift Testing reports a duration that includes time a `@MainActor` test waited for the main actor.
So durations from a parallel run are not a cost profile. Measure one test with
`-parallel-testing-enabled NO`.
