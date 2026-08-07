---
type: Tool
title: Build system and xcodebuild invocation
description: How the Makefile and the tools/ scripts agree on one xcodebuild invocation -
  scheme, configuration, derived-data cache, compilation caching, output filtering,
  warnings-as-errors, products path - and what each knob overrides.
tags: [tool, build, make, xcodebuild]
timestamp: 2026-08-07T00:00:00Z
---

# Build system and xcodebuild invocation

`make` is the single automation entrypoint (AGENTS.md "Build, run, test"). Every target
that compiles, tests, or installs runs `xcodebuild`, and every one of them builds its
command line from one definition, so scheme, configuration, cache location, and output
volume cannot drift apart per target. The scripts under `tools/` run their own
`xcodebuild` commands and share the same values through the environment.

## Contents

* The shared invocation
* Build settings: the Config/ xcconfig layer
* Compilation caching
* Signing
* Output volume and the transcripts in logs/
* Swift warnings are errors
* Built-products path
* tools/xcodebuild-lib.sh
* Known limits

## The shared invocation

`Makefile` defines the common core once:

```make
xcb = xcodebuild -project $(PROJECT) -scheme $(1) -configuration $(2) \
    $(XCODEBUILD_DD) $(XCODEBUILD_FLAGS)
XCB_APP     := $(call xcb,$(SCHEME),$(CONFIG))
XCB_CLI     := $(call xcb,$(CLI_SCHEME),$(CONFIG))
XCB_RELEASE := $(call xcb,$(SCHEME),Release)
XCB_TEST    := $(XCB_APP) -destination '$(DESTINATION)'
```

A target then adds only its action and the flags specific to it: `build` is
`$(XCB_RUN) build $(XCB_APP) build`, `test` adds `-resultBundlePath` and
`-testPlan UnitTests`, `install` adds `ARCHS=arm64`. `make -n build cli test
install` shows the shared prefix on every line, which is the check that the consolidation
still holds.

| Knob | Default | Overrides |
| --- | --- | --- |
| `CONFIG` | `Debug` | Configuration for `build`, `cli`, `test`, `app-path`, `cli-path`. `install` is always Release. |
| `DESTINATION` | `platform=macOS` | Test destination. |
| `DERIVED_DATA` | `$(CURDIR)/DerivedData` | Build cache; exported to the scripts as `OPENSKY_DERIVED_DATA`. |
| `XCODEBUILD_FLAGS` | empty | Extra flags or build settings, e.g. CI's `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`. |
| `OPENSKY_XCODEBUILD_RAW` | unset | `=1` prints the whole transcript instead of the filtered stream. |

## Build settings: the Config/ xcconfig layer

Every build setting lives in a text file under `Config/`, and the ten build
configurations in `opensky.xcodeproj/project.pbxproj` hold an empty `buildSettings` block
plus a `baseConfigurationReference` naming one of them. Changing a setting is a one-line
diff in a file a review can read, and the pbxproj — the worst merge-conflict surface in a
repository that runs parallel linked worktrees — no longer carries five near-identical
copies of the same values.

```text
Config/
├── Base.xcconfig            deployment target, SDK, Swift mode, warnings, versioning
├── Debug.xcconfig           #include Base + -Onone, dwarf, testability
├── Release.xcconfig         #include Base + wholemodule, dSYM, VALIDATE_PRODUCT
├── Signing.xcconfig         CODE_SIGN_IDENTITY and DEVELOPMENT_TEAM, one identity
├── App.xcconfig             opensky: bundle id, Info.plist keys, ffmpeg link + rpath
├── CLI.xcconfig             openskycli: bridging header, ffmpeg link + rpath
├── Tests.xcconfig           openskyTests: TEST_HOST, BUNDLE_LOADER
├── UITests.xcconfig         openskyUITests: TEST_TARGET_NAME
├── UnitTests.xctestplan     scheme default: openskyTests alone
└── UITests.xctestplan       openskyUITests alone
```

The two test plans sit here for the same reason as the xcconfigs: they are checked-in,
reviewable configuration the scheme points at, rather than settings buried in the project
file or flags spread across the `Makefile`. See [Testing setup](/testing.md).

The two levels do different jobs. `Debug.xcconfig` and `Release.xcconfig` are the
project's base configurations, so they cover every target; the four target files sit above
them in the setting hierarchy and each applies to both configurations of one target,
because no target here wants a different bundle identifier or link line in Debug than in
Release. A per-configuration target setting, if one is ever needed, is the one case that
still belongs in the pbxproj — target build settings are the only level above the target
xcconfig.

The move preserved every effective value: `xcodebuild -showBuildSettings` for all four
targets in both configurations differs only by the two new `OPENSKY_*` variables the
signing indirection introduces.

`tools/lint/swift-baseline.sh` reads `SWIFT_VERSION` from `Config/*.xcconfig` as well as
from the pbxproj, so the Swift 6 language-mode gate still fails on a configuration that
slips back. See [Swift toolchain and language mode](/tools/swift-toolchain.md).

## Compilation caching

`COMPILATION_CACHE_ENABLE_CACHING = YES` in `Config/Base.xcconfig` turns on the compilation
caching Xcode 26 ships opt-in. Every compile task is keyed on its full command line and its
inputs, the result is stored in a content-addressed store, and a later task with the same
key replays that result instead of running the compiler. Explicit modules, which the cache
needs to key module builds separately from the sources that import them, are already on by
default here: `-showBuildSettings` reports `CLANG_ENABLE_EXPLICIT_MODULES = YES` and
`SWIFT_ENABLE_EXPLICIT_MODULES = YES` with nothing in `Config/` setting either.

The store needs no configuration to land in the right place. `COMPILATION_CACHE_CAS_PATH`
defaults to `$(DERIVED_DATA)/CompilationCache.noindex`, so it follows the
`-derivedDataPath` every `make` target passes and sits on the external volume beside the
build cache it belongs to, not on the boot disk. `make clean` keeps that one directory and
removes everything else under `DerivedData/`; `make clean DEEP=1` removes it too. `make
prune` needs no rule of its own, because it deletes a departed worktree's whole
`DerivedData/`.

Measured on this machine at Xcode 26.6, wall clock from `/usr/bin/time`, `make build` in
Debug unless the row says otherwise (issue #341):

| Flow | Caching off | Caching on | Cache hits |
| --- | --- | --- | --- |
| Cold build, empty store | 45.1 s | 46.0 s | 0, populating |
| Rebuild after the build tree is deleted, store warm | 45.1 s | 9.8 s | 106 hits, 0 misses |
| Rebuild after `make clean` | 45.1 s | 18.2 s | populated by earlier builds |
| `make install` (Release), cold, empty store | | 779.8 s | 0, populating |
| `make install` (Release) after `make clean` | 779.8 s | 29.5 s | populated by the run above |
| An edit reverted back to a state already built | n/a | 16.7 s | |
| Branch switch away (three commits) | 40.1 s | 43.0 s | 1 |
| Branch switch back | 22.7 s | 23.0 s | 2 |
| `make cli` straight after `make build` | 25.7 s | 29.5 s | 1 |
| One-file edit, rebuild | 43.8 s, 77.7 s | 29.8 s, 76.2 s | |

The one flow it transforms is a rebuild of a state this checkout has compiled before with
the intermediates gone. In Debug that is about four and a half times faster with every
compile task hit; in Release it is the difference between thirteen minutes and half a
minute, because Release compiles the whole module as one task and there is nothing
incremental about redoing it. The rest of the table is the reason the setting is worth
understanding rather than assuming.

* **A branch switch gains nothing.** Switching in place leaves `DerivedData/Build` intact,
  so the build system's own incremental state already decides what to recompile and the
  cache is asked almost nothing.
* **`make cli` does not reuse `make build`.** `opensky/Engine/` compiles into a different
  module for `openskycli`, so the command line differs and so does every key. That run is
  slower with caching on, by roughly the cost of writing its own results into the store.
* **An ordinary incremental edit is unaffected.** Repeated samples of the same one-file
  edit ranged from 30 to 78 seconds either way, which is machine noise swamping any
  difference. This matches how Apple positions the feature: it is for rebuilding previously
  compiled states, not for the edit-build loop.
* **A second worktree cannot share the store.** Pointing a fresh worktree's
  `COMPILATION_CACHE_CAS_PATH` at a warm store built in another one hit 72 entries and took
  45.2 s against a 45.1 s baseline. The hits are all SDK module builds, whose command lines
  name only SDK paths; every project source task missed, because its key embeds the
  absolute source path and no `-file-prefix-map` or `-cache-replay-prefix-map` appears in
  the compile commands Xcode generates. Sharing a store the way `.vendor/ffmpeg` is shared
  would buy no wall clock, so nothing does it.

The cost is disk. The store reached 363 MB after one Debug app build and 1.1 GB after
roughly fifteen builds across two commits, per worktree, and it is not visibly bounded:
`COMPILATION_CACHE_LIMIT_SIZE` and `COMPILATION_CACHE_LIMIT_PERCENT` exist as build
settings, but setting `COMPILATION_CACHE_LIMIT_SIZE` to 100 MB against a 1.1 GB store
shrank nothing over a build, so neither is relied on here. `make clean DEEP=1` and `make
prune` are the two things that reclaim it.

`COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES` makes each cached task report its key
and whether it replayed. It is not checked in, because it adds several lines per task to
every transcript; pass it when measuring:

```sh
make build XCODEBUILD_FLAGS='COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES'
grep -c 'Cache hit' logs/build/latest/build.log
```

CI gets the setting too, since it comes from the xcconfig, and gains nothing from it: a
runner starts with an empty store every time and pays the one to two percent a populating
build costs. That is small enough not to be worth a CI-only override, which would be one
more way for `ci.yml` and the local gate to drift.

## Signing

`Config/Signing.xcconfig` names the identity and team, and every target that produces a
bundle includes it: the app, the CLI, the app-hosted unit test bundle, and the UI test
runner.

```text
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = 92X872A57T
#include? "Local.xcconfig"
```

The identity is checked in on purpose, and ad-hoc is not the default. macOS keys TCC
grants to a binary's code signature, and ad-hoc signing produces a *different* signature
on every build, so an ad-hoc build is a new application every time. Every grant the test
surface depends on is then requested again, interactively, mid-run:

* `openskyUITests-Runner.app` is the process that asks to drive the app, so `make test-ui`
  stops on an Automation dialog ("opensky would like to access data from other apps") on
  every run.
* Screen Recording, which the screenshot tooling needs.
* Access to the external volume holding the game install, which shows up as a real-data
  test host parked in `open()` while the same path lists instantly from a shell.

`make test-ui` used to pass `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` of its own accord, and
a command-line build setting wins over every xcconfig, so the UI test run signed ad-hoc no
matter what the configuration said — the one target where a stable signature matters most.
That override is gone; `make test-ui` now signs like every other target.

Deriving the identity per machine instead was tried and reverted: it has the same failure
mode whenever the derivation comes up empty, and it makes the signature depend on machine
state that nothing in the repository can check. One identity in shared configuration means
a checkout builds, and keeps its permissions, with no local setup.

A machine without that certificate, and CI, override on the command line, which wins over
every xcconfig layer:

```sh
make test XCODEBUILD_FLAGS='CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='
```

A gitignored `Config/Local.xcconfig` is the persistent form of the same override. Nothing
creates it; write one by hand, assigning `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM`
directly, and the `#include?` at the end of `Signing.xcconfig` picks it up.

Check what a build actually got:

```sh
codesign -dv --verbose=2 DerivedData/Build/Products/Debug/opensky.app
codesign -dv --verbose=2 DerivedData/Build/Products/Debug/openskyUITests-Runner.app
```

`Authority=Apple Development: ...` with a `TeamIdentifier` is right; `Signature=adhoc` is
the state that causes repeated prompts.

## Output volume and the transcripts in logs/

Per-file compile lines and the one line per passing test are the bulk of what a build or
test run prints and carry nothing a green run needs; they are exactly what you want when
something breaks. `tools/xcodebuild-run.sh` resolves that: it takes a log name and a full
xcodebuild command line, tees the entire transcript to
`logs/<name>/<UTC timestamp>/<name>.log`, and passes
stdout through `xcodebuild_summary` — diagnostics, tests that did not pass, and the
closing status line. A failing run then prints the whole log, so a failure message can
never exist only in a file. A green `make build` prints two lines against a transcript of
roughly 1,300.

`xcodebuild -quiet` cannot do this: it decides what to print before the text exists,
leaving no complete copy anywhere, and it also drops `** TEST SUCCEEDED **`. Every target
and script that runs `xcodebuild` for its output goes through the wrapper instead —
`build`, `cli`, `test`, `test-one`, `install`, `tools/test-ui.sh`, and
`tools/realtest.sh`. `tools/probe.sh` keeps its own `probe.log` because the CLI
output it greps is the point of the run, not the build.

Where that transcript lands, how a wrapper script keeps a whole run's output in one
directory, and how `make prune` ages it out are the run-output convention:
[Run output layout and make prune](/tools/run-output.md).

## Swift warnings are errors

`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` sits in `Config/Base.xcconfig`, next to the
`MTL_TREAT_WARNINGS_AS_ERRORS` that has always governed the shaders, so it covers
`opensky`, `openskycli`, `openskyTests`, and `openskyUITests` at once rather than per
target. SwiftLint never sees a compiler diagnostic, so before this setting nothing
stopped warnings from accumulating: the test targets had drifted to about a hundred of
them, and because a warning is signal the output filter keeps, a `make test` that
recompiled them printed roughly a hundred lines instead of the three an incremental run
prints (issue #350).

The consequence to expect is that a toolchain upgrade which adds a deprecation warning
breaks the build outright rather than adding a line to the transcript. That is the same
trade the project already accepts for SwiftLint and for the Metal compiler, and the fix is
to fix the diagnostic. Do not switch the setting off to get a build through.

## Built-products path

`xcodebuild -showBuildSettings` takes several seconds, and `app-path`, `cli-path`, and
`tools/probe.sh` used it only to learn `BUILT_PRODUCTS_DIR`. For a macOS scheme built with
`-derivedDataPath`, that directory is always:

```text
$(DERIVED_DATA)/Build/Products/$(CONFIG)
```

The Makefile computes it as `PRODUCTS`, the scripts as `xcodebuild_products_dir CONFIG`.
This holds because every OpenSky target builds for macOS only; a scheme built for another
platform would add a platform suffix (`Debug-iphoneos`) and break the assumption.

## tools/xcodebuild-lib.sh

Sourced, never executed. It is the shell half of the same agreement: it defaults
`OPENSKY_DERIVED_DATA` for a script run outside `make`, and provides
`xcodebuild_products_dir` and the `xcodebuild_summary` stdin filter.

`tools/realtest.sh` shares the ordinary `$OPENSKY_DERIVED_DATA` tree: selecting a test plan
changes no build setting, so the separate tree it once kept bought nothing. Its `-O` mode is
the exception. That one *does* change a build setting — the optimization level, for the
physics perf gate — so it builds into `$OPENSKY_DERIVED_DATA-optimized` rather than making
every alternation with `make test` rebuild the engine. Both stay on this volume, because the
boot disk cannot hold either, and `make prune` removes both from a departed worktree. See
[Testing setup](/testing.md).

## Known limits

* Two concurrent `xcodebuild` invocations against the same derived-data tree deadlock
  until the tool timeout. Let one finish before starting another
  ([Testing setup](/testing.md)).
