---
type: Tool
title: Build system and xcodebuild invocation
description: How the Makefile and the tools/ scripts agree on one xcodebuild invocation -
  scheme, configuration, derived-data cache, output filtering, warnings-as-errors, products
  path - and what each knob overrides.
tags: [tool, build, make, xcodebuild]
timestamp: 2026-08-04T00:00:00Z
---

# Build system and xcodebuild invocation

`make` is the single automation entrypoint (AGENTS.md "Build, run, test"). Every target
that compiles, tests, or installs runs `xcodebuild`, and every one of them builds its
command line from one definition, so scheme, configuration, cache location, and output
volume cannot drift apart per target. The scripts under `tools/` run their own
`xcodebuild` commands and share the same values through the environment.

## Contents

* The shared invocation
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
`-only-testing:openskyTests`, `install` adds `ARCHS=arm64`. `make -n build cli test
install` shows the shared prefix on every line, which is the check that the consolidation
still holds.

| Knob | Default | Overrides |
| --- | --- | --- |
| `CONFIG` | `Debug` | Configuration for `build`, `cli`, `test`, `app-path`, `cli-path`. `install` is always Release. |
| `DESTINATION` | `platform=macOS` | Test destination. |
| `DERIVED_DATA` | `$(CURDIR)/DerivedData` | Build cache; exported to the scripts as `OPENSKY_DERIVED_DATA`. |
| `XCODEBUILD_FLAGS` | empty | Extra flags or build settings, e.g. CI's `CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=`. |
| `OPENSKY_XCODEBUILD_RAW` | unset | `=1` prints the whole transcript instead of the filtered stream. |

## Output volume and the transcripts in logs/

Per-file compile lines and the one line per passing test are the bulk of what a build or
test run prints and carry nothing a green run needs; they are exactly what you want when
something breaks. `tools/xcodebuild-run.sh` resolves that: it takes a log name and a full
xcodebuild command line, tees the entire transcript to `logs/<name>.log`, and passes
stdout through `xcodebuild_summary` — diagnostics, tests that did not pass, and the
closing status line. A failing run then prints the whole log, so a failure message can
never exist only in a file. A green `make build` prints two lines against a transcript of
roughly 1,300.

`xcodebuild -quiet` cannot do this: it decides what to print before the text exists,
leaving no complete copy anywhere, and it also drops `** TEST SUCCEEDED **`. Every target
and script that runs `xcodebuild` for its output goes through the wrapper instead —
`build`, `cli`, `test`, `test-one`, `install`, `tools/test-ui.sh`, and
`tools/realtest.sh`. `tools/probe.sh` keeps its own `logs/probe.log` because the CLI
output it greps is the point of the run, not the build.

## Swift warnings are errors

`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` sits in both project-level build configurations,
next to the `MTL_TREAT_WARNINGS_AS_ERRORS` that has always governed the shaders, so it
covers `opensky`, `openskycli`, `openskyTests`, and `openskyUITests` at once rather than
per target. SwiftLint never sees a compiler diagnostic, so before this setting nothing
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

`tools/realtest.sh` keeps its own cache at `$OPENSKY_DERIVED_DATA/opensky-realtest`, so a
real-data run never invalidates the ordinary build tree, but stays on the same volume
because the boot disk cannot hold either. See [Testing setup](/testing.md).

## Known limits

* `make test` passes `-only-testing:openskyTests`, which names the unit-test target
  explicitly instead of subtracting the UI one. It does not stop `xcodebuild` from
  compiling `openskyUITests`: the tool builds every buildable in the scheme's Test action
  before it consults the selectors. Removing that build cost needs checked-in test plans
  (issue #346), not a flag.
* Two concurrent `xcodebuild` invocations against the same derived-data tree deadlock
  until the tool timeout. Let one finish before starting another
  ([Testing setup](/testing.md)).
