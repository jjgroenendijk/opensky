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
The `OpenSky` scheme has seven plans, under `Config/TestPlans/`:

| Plan | Test targets | Used by |
| --- | --- | --- |
| `UnitTests.xctestplan` | `OpenSkyTests` and every package test target | `make test-unit`, `make test-unit LOCALE=nl`. The scheme default |
| `Parser.xctestplan` | the unit plan's targets, only the tests tagged `parser` | `make test-unit TAG=parser` |
| `GPU.xctestplan` | the unit plan's targets, only the tests tagged `gpu` | `make test-unit TAG=gpu` |
| `UITests.xctestplan` | `OpenSkyUITests` | `make test-ui` |
| `RealData.xctestplan` | `OpenSkyRealDataTests`, plus the data root | `make test-real` |
| `Perf.xctestplan` | `OpenSkyRealDataTests`, only the tests tagged `perf`, plus the data root | `make test-real PERF=1` |
| `Sanitizers.xctestplan` | the unit plan's targets, one configuration per sanitizer | `make test-sanitize SAN=thread`, `SAN=address` |

The unit plan has two configurations. `Unit` is the normal run, and every command but one names it
with `-only-test-configuration`, because xcodebuild runs every configuration of a plan when none is
named. `Locale` sets the language to `nl` and the region to `NL`, where the decimal separator is a
comma, and `make test-unit LOCALE=nl` runs it. It catches text parsing that reads the user's
locale. Both configurations share one build, because neither changes a build setting.

`make lint-test-plans`, part of `make lint`, checks the rules below that a machine can check: every
plan is in the scheme, sets the timeouts, sets no repetition, and selects no test by name. It also
checks that the Perf plan selects only the `perf` tag with the RealData data root, that each tag
plan selects only its tag, and that the sanitizer and tag plans list the unit plan's targets and set
its environment, such as the shader library path.

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
| `UITests` | not measured ([permission grants](/tools/environment.md#permission-grants)) | 300 s | 600 s |
| `RealData`, `Perf` | 152 s | 600 s | 1800 s |
| `Sanitizers` | 25 s | 600 s | 1800 s |

A parallel run reports a test's time including its wait for the main actor, up to 20 s for a unit
test that alone takes milliseconds, so the unit allowance leaves room for that. A test that fails on
its allowance is a hang to find, not a limit to raise.

## Tags

Swift Testing tags label suites and tests: `.gpu`, `.slow`, `.acceptance`, `.perf`, and `.parser`,
from `Tests/TagsTesting/Tags.swift`. `Tests/AGENTS.md` says which suite carries which, and
`make lint-test-tags` checks the ones a machine can find.

A plan's `selectedTests` matches no Swift Testing test, but its `selectedTags` does. Each test
target entry takes `"selectedTags" : { "tags" : [ "perf" ] }`. The Perf plan ran exactly the two
tagged tests of `OpenSkyRealDataTests` this way. xcodebuild has no flag that selects a tag, so a tag
run needs its own plan: `Parser` and `GPU` are the unit plan with every target narrowed to one tag.

A tag cannot replace a plan. A plan chooses the bundles that are built and the environment of the
host; a tag only chooses tests inside them. So the real-data suites stay in their own bundle.

`make test-report` prints passed, failed, and time per tag. A result bundle does not carry the tags,
so the report reads them from the sources and matches each test by suite and name.

## Repeat and locale runs

`make test-unit T='Suite/test()' N=100` passes `-run-tests-until-failure -test-iterations N` and
stops at the first failure. It is a make target and not a plan configuration on purpose. A plan with
`testRepetitionMode` would repeat every run that uses the plan, and a retry on failure hides the
failure a flaky hunt is looking for. `make lint-test-plans` fails a plan that sets either.

## Attachments

A green unit run writes a result bundle of about 113 MB with no attachments at all. The largest part
is the coverage archive. So the plans leave `userAttachmentLifetime` and `systemAttachmentLifetime`
at their defaults: deleting attachments on success would save nothing.

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

A warm `xcodebuild test` spends most of its time on the build system starting, resolving the scheme
and plan, and checking the whole graph, not on the tests. Measured on 2026-10-02 with nothing to
compile: one unit suite took 15 to 21 s, one real-data test 25 s, the `Parser` plan 47 s, and the
whole unit plan 56 s. Each run pays the start-up, so batch edits into one run.

`make test-real` and `make test-sanitize` start `tools/memguard.sh` beside the
call and turn parallel testing off, so one test host runs and the watchdog's cap is per run. `CAP=MB`
changes the cap.

## The RealData plan

`Config/TestPlans/RealData.xctestplan` holds a literal install path. A plan value is not
macro-expanded, so `$(OPENSKY_DATA_ROOT)` would arrive as those characters. The Perf plan holds the
same path, and `make lint-test-plans` fails when the two differ. An exported `OPENSKY_DATA_ROOT`
does not change it. To use another install, edit both plans.

A plan's `selectedTests` does not match Swift Testing tests: selecting any runs zero tests. So the
plan selects the whole target, which does work. That is why the real-data suites are their own
bundle. Before, they lived in `OpenSkyTests`: every unit build compiled them though they always
skipped there, and the plan needed a long hand-kept list of suites. The shared fixtures now compile
into both bundles instead. Types that mixed a fixture with `@Test` methods were split into a fixture
in `Tests/TestSupport/` and tests in an extension under `Tests/OpenSkyTests/`, so no test name changed.

`make realdata-plan`, part of `make lint`, checks that every suite with a `@Test` that reads
`RealDataEnvironment` or declares a `dataRoot: GameDataRoot?` is in `Tests/OpenSkyRealDataTests/`,
that the plan selects that target and nothing narrows it, and that no plan lists an app-hosted
bundle beside `OpenSkyUITests`.

## Code coverage

The unit, UI, and sanitizer plans gather line coverage for the `OpenSky` target and the package
modules only, so the number is about engine code, not the test bundles. `make test-unit` gathers it
and `make test-report` prints it. There is no separate target and no `-enableCodeCoverage` flag.
`ENABLE_CODE_COVERAGE` defaults to `YES` in Xcode, so coverage was already gathered on every run and
thrown away. Scoping it cost nothing measurable: turning it on explicitly recompiled nothing and
changed the time within noise.

The plan's target list scopes only the report. A test build compiles every target with
`-profile-coverage-mapping -profile-generate`, test bundles and fixtures included. A plain `build`
compiles without them, and both write the same package intermediates under `DerivedData/Build`. So
`make cli` after `make test-unit` used to recompile the whole engine, and the next test build did it
again. The `Makefile` therefore passes `CLANG_COVERAGE_MAPPING=YES` on every Debug command line
(`COVERAGE_Debug`), and `tools/probe.sh` does the same. It has to be the command line: xcodebuild
sets this setting per action above `Config/Build/Overrides.xcconfig`, so an xcconfig value does not
reach the compiler. A Release build stays without coverage. An instrumented program writes
`default.profraw` into its working directory when it exits; `.gitignore` covers it.

`make test-report` and `make coverage-floor` read `DerivedData/Build/ProfileData/*/Coverage.profdata`
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
| `Thread` | `threadSanitizerEnabled` | `DerivedData/Build/Products/Variant-TSan/` |
| `Address` | `addressSanitizer.enabled`, `undefinedBehaviorSanitizerEnabled` | `.../Variant-ASan-UBSan/` |

The two sanitizers cannot share a build. xcodebuild builds every configuration in a plan even when
told to run one, so each target narrows what runs, not what compiles. That is why this is its own
plan: as configurations on `UnitTests`, the sanitized builds would compile on every `make
test-unit`. The first run of each configuration recompiles everything, so it is an occasional check,
like `make test-real`. A sanitizer report shows as a failing test. Both configurations were clean
when added, so a new report is a regression, and a real one becomes its own GitHub issue.

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
