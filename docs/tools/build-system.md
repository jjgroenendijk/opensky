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
* Build settings: the Config/ xcconfig layer
* Signing and Config/Local.xcconfig
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
├── Signing.xcconfig         CODE_SIGN_IDENTITY and DEVELOPMENT_TEAM indirection
├── App.xcconfig             opensky: bundle id, Info.plist keys, ffmpeg link + rpath
├── CLI.xcconfig             openskycli: bridging header, ffmpeg link + rpath
├── Tests.xcconfig           openskyTests: TEST_HOST, BUNDLE_LOADER
├── UITests.xcconfig         openskyUITests: TEST_TARGET_NAME, ad-hoc signing
└── Local.example.xcconfig   template for the gitignored Config/Local.xcconfig
```

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

## Signing and Config/Local.xcconfig

No signing identity is checked in. `Base.xcconfig` declares the two inputs, defaults them
to ad-hoc signing, then optionally includes a per-developer file:

```text
OPENSKY_CODE_SIGN_IDENTITY = -
OPENSKY_DEVELOPMENT_TEAM =
#include? "Local.xcconfig"
```

`Signing.xcconfig` maps those onto `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` and is
included by the app, the CLI, and the unit test bundle. The UI test runner pins itself to
`-` instead and does not include it. `#include?` is the optional form, so a checkout
without `Config/Local.xcconfig` builds ad-hoc and silently rather than failing on a
missing file, which is the same signing CI passes on the command line. A command-line
build setting still wins over both layers.

`tools/config-local.sh` creates `Config/Local.xcconfig` when it is absent: `make
bootstrap` runs it, and so does every make target that drives `xcodebuild`, next to
`vendor-link`. It resolves the contents in this order:

1. A linked worktree copies the main checkout's file, so a dev-signed setup does not
   quietly become ad-hoc in a new worktree.
2. Otherwise it reads the first `Apple Development` identity out of the login keychain
   (`security find-identity -v -p codesigning`) and that certificate's `OU` field as the
   Team ID (`security find-certificate -c ... | openssl x509 -noout -subject`), and writes
   both. Reading the team off the certificate beats asking anyone to copy it out of the
   developer portal, and it is the value Xcode matches against.
3. Only with no identity, or an identity whose team cannot be read, does it fall back to
   copying the ad-hoc template. `CODE_SIGN_STYLE` is `Automatic`, and a real identity
   without a team fails to resolve a provisioning profile rather than degrading to ad-hoc,
   so the two values are written together or not at all.

The file is written once and never regenerated, so editing it sticks. A missing
`Config/Local.example.xcconfig` is the one hard failure, since it means the checkout is
broken.

Ad-hoc is a fallback, not the intended local setup. The unit test bundle is app-hosted
(`TEST_HOST` points at the built `opensky.app`) and the UI tests drive the real app, so
both depend on the app's signature. Ad-hoc signing produces a *different* signature on
every build, and macOS keys TCC grants to it: each build reads as a new application, so
Automation ("opensky would like to access data from other apps"), the screenshot
permissions, and access to the external volume the game install sits on are all requested
again, interactively, mid-run. A real Apple Development identity gives the app a stable
designated requirement and the grants persist. Verify what a build actually got with:

```sh
codesign -dv --verbose=2 DerivedData/Build/Products/Debug/opensky.app
```

`Authority=Apple Development: ...` with a `TeamIdentifier` is right; `Signature=adhoc` is
the state that causes repeated prompts.

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
