---
type: Tool
title: Build system and xcodebuild invocation
description: How the Makefile and the tools/ scripts share one xcodebuild invocation - the Config/
  xcconfig layer, the OpenSkyShaderTypes module, compilation caching across worktrees, signing,
  output filtering, warnings as errors, and the products path.
tags: [tool, build, make, xcodebuild]
---

# Build system and xcodebuild invocation

`make` is the one entry point. Every target that compiles, tests, or installs runs `xcodebuild`, and
each builds its command line from one definition, so the scheme, configuration, cache location, and
output cannot drift apart per target. Scripts under `tools/` share the same values through the
environment.

## The shared invocation

The `Makefile` defines the common part once:

```make
xcb = xcodebuild -project $(PROJECT) -scheme $(1) -configuration $(2) \
    $(XCODEBUILD_DD) $(XCODEBUILD_FLAGS)
XCB_APP     := $(call xcb,$(SCHEME),$(CONFIG))
XCB_CLI     := $(call xcb,$(CLI_SCHEME),$(CONFIG))
XCB_RELEASE := $(call xcb,$(SCHEME),Release)
XCB_TEST    := $(XCB_APP) -destination '$(DESTINATION)'
```

A target adds only its action and its own flags. `make -n build cli test install` shows the shared
prefix on every line, which checks that it still holds.

The cache is on the internal disk because the data volume is a USB disk that writes at about
135 MB/s against the internal disk's 2 GB/s, and a build writes gigabytes of intermediates. The
compilation cache store stays on the data volume: it is tens of gigabytes, more than the boot
volume can hold, and a replayed task reads a few files from it rather than streaming.

## One build at a time

Every command that compiles takes a machine-wide lock first, `build.lock` under `CACHE_ROOT`, in
`tools/xcodebuild-lib.sh`. A second session's build waits and prints the owner's pid every
30 seconds; a lock whose owner is gone is taken over. The machine has four performance cores and
16 GB, and before the lock, up to eleven builds ran at once and each took many times longer than
alone. `make test-rerun` takes no lock, because it compiles nothing.

| Knob | Default | Changes |
| --- | --- | --- |
| `CONFIG` | `Debug` | The configuration for `build`, `cli`, `test`, `app-path`, and `cli-path`. `install` is always Release |
| `DESTINATION` | `platform=macOS` | The test destination |
| `CACHE_ROOT` | `~/Library/Caches/OpenSky` | Where every checkout's build cache lives, on the internal disk, exported as `OPENSKY_CACHE_ROOT` |
| `DERIVED_DATA` | `$(CACHE_ROOT)/<checkout folder name>` | The build cache, exported to scripts as `OPENSKY_DERIVED_DATA` |
| `COMPILATION_CACHE` | `<main checkout>/DerivedData/CompilationCache.noindex` | The compilation cache store every checkout shares, exported as `OPENSKY_COMPILATION_CACHE` |
| `XCODEBUILD_FLAGS` | empty | Extra flags or build settings |
| `OPENSKY_XCODEBUILD_RAW` | unset | `=1` prints the whole transcript instead of the filtered output |
| `OPENSKY_MAX_ERRORS` | `40` | How many unique errors the filtered output prints |

## Build settings in Config/

Every build setting is in a text file under `Config/Build/`. The project file has empty
`buildSettings` and names these files as bases. So a setting change is a one-line diff a review can
read, and the project file, the worst merge conflict surface, holds no copies of the values.

```text
Config/
├── Build/
│   ├── Base.xcconfig        deployment target, SDK, Swift mode, warnings, versioning
│   ├── Debug.xcconfig       #include Base + -Onone, dwarf, testability, prefix mapping
│   ├── Release.xcconfig     #include Base + wholemodule, dSYM, VALIDATE_PRODUCT
│   ├── Signing.xcconfig     CODE_SIGN_IDENTITY and DEVELOPMENT_TEAM, one identity
│   ├── App.xcconfig         OpenSky: bundle id, Info.plist keys, ffmpeg link + rpath
│   ├── CLI.xcconfig         OpenSkyCLI: binary name, isolation default, ffmpeg link + rpath
│   ├── Tests.xcconfig       the unit bundles: TEST_HOST, BUNDLE_LOADER
│   ├── UITests.xcconfig     OpenSkyUITests: TEST_TARGET_NAME
│   └── Overrides.xcconfig   above every target, package targets too
└── TestPlans/
    └── *.xctestplan         the four test plans (see test runs)
```

The test plans are in `Config/TestPlans/` for the same reason ([test runs](/tools/test-runs.md)).
`Debug.xcconfig` and `Release.xcconfig` are the project's base configurations for every target. The
target files sit above them and apply to both configurations of one target. Only a setting that
differs per configuration inside one target still belongs in the project file.

The project's files never reach a package target, whose settings come from `Package.swift`.
`Overrides.xcconfig` is the one place for a setting that has to: the `Makefile` and
`tools/xcodebuild-lib.sh` export `XCODE_XCCONFIG_FILE` pointing at it, and xcodebuild applies that
file above every target in the build. A build started from the Xcode window does not read it. Today
it only turns off a missing-dependency check that is wrong for package framework variants
([environment](/tools/environment.md#package-framework-variants-warn-about-declared-dependencies)).

`tools/lint/swift-baseline.sh` reads `SWIFT_VERSION` from `Config/Build/*.xcconfig` and the project
file, so the Swift 6 mode check still catches a configuration that slips back
([Swift toolchain](/tools/swift-toolchain.md)).

## The OpenSkyShaderTypes module

Structs and constants shared by Swift and the Metal shaders live in
`Sources/OpenSkyShaderTypes/ShaderTypes.h`, next to a `module.modulemap` that declares
`module OpenSkyShaderTypes { header "ShaderTypes.h" export * }`. The folder is a clang target of the
Swift package, so a file that writes `import OpenSkyShaderTypes` sees the types and no other file
does. SwiftPM links a clang target's object file, so the target also holds `ShaderTypes.m`, which
declares nothing. It is Objective-C because the header imports Foundation.
`MTL_HEADER_SEARCH_PATHS` points at the same folder, so `Shaders.metal` keeps
`#import "ShaderTypes.h"`.

There is no bridging header. A bridging header is visible to every Swift file in its target, so every
file depended on the shared header whether it used it or not, and `OpenSkyCLI` had to name the app's
header by path. The header also pulls in Foundation and `simd`, so files that relied on that now
import them themselves, as `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` asks. The module did
not make incremental builds smaller. Editing the header and editing an unrelated
parser file both recompile the whole target, because the module-wide `.swiftmodule` is an input to
every compile task. The reason for the module is explicit dependencies and two decoupled targets.

## Compilation caching

`COMPILATION_CACHE_ENABLE_CACHING = YES` in `Config/Build/Base.xcconfig` turns on Xcode 26's compilation
cache. Each compile task is keyed on its command line and inputs, and a task with a known key
replays the stored result instead of compiling. Explicit modules, which the cache needs, are already
on by default. The store is `$(COMPILATION_CACHE)`, passed as `COMPILATION_CACHE_CAS_PATH` on every
command line, so it stays on the data volume while the build cache is on the internal disk.
`make clean` keeps it; `make clean DEEP=1` removes it.

What it helps and what it does not:

- It helps a rebuild of a state compiled before, after the build folder is gone. In Debug that was
  about four and a half times faster. In Release, which compiles the module as one task, it was half
  a minute instead of thirteen.
- A branch switch gains nothing: switching in place keeps `Build/` in the cache, so the build
  system's own incremental state decides.
- A cache hit leaves the Swift driver's incremental record saying "needs build"
  ([environment](/tools/environment.md#a-compilation-cache-hit-leaves-the-driver-record-dirty)).
  Each switch between build contexts, such as `make build-cli` then `make test-unit`, then
  compiles those modules again and relinks everything above them. So the `OpenSky` scheme
  builds `openskycli` for testing, and the Debug `make build-app` and `make build-cli` use
  `build-for-testing` on the `AgentControl` plan, so every Debug build is the test context.
- An ordinary edit-and-build loop is unaffected. Apple describes the feature as being for rebuilding
  states compiled before.

`COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES` makes each task report its key and whether it hit.
It is not checked in, because it adds lines to every transcript. Pass it when measuring:

```sh
make build-app XCODEBUILD_FLAGS='COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES'
grep -c 'Cache hit' logs/build/latest/build.log
```

The store grows to gigabytes and is not visibly bounded: `COMPILATION_CACHE_LIMIT_SIZE` set below
the store's size shrank nothing. `make clean DEEP=1` and `make prune` reclaim it. CI starts its
store over by size instead ([CI](/tools/ci.md#caches)).

### One store for every worktree

Without prefix mapping, every project task's key holds the absolute source path, so a new worktree
hit only SDK module builds. `Config/Build/Debug.xcconfig` sets `SWIFT_ENABLE_PREFIX_MAPPING`,
`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING`, and
`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`. Xcode then rewrites the checkout path to `/^src`, derived-data
temporaries to `/^derived`, and products to `/^built`, so the same source gets the same key in any
worktree. Every checkout passes the same store path, the main checkout's, so a fresh worktree's
first unit build takes seconds instead of minutes. `make link-shared`, run first by every
building target, links a worktree's `.vendor/ffmpeg` to the main checkout's.

The mapping has three costs:

- A replayed task writes no index data. Periphery reads the index, so `make health` builds
  uncached into the `-index` cache tree ([code-health automation](/decisions/code-health-automation.md)).
- `#filePath` reads `/^src/...`, so a test cannot find the checkout from it. Real-data suites find
  `logs/` by walking up from the test bundle to the folder holding `OpenSky.xcodeproj`.
- Debug info names sources `/^src/...`. A command-line `lldb` needs
  `settings set target.source-map /^src <checkout>`.

## Signing

`Config/Build/Signing.xcconfig` names the identity and team, and every target that makes a bundle
includes it: the app, the CLI, the unit test bundles, and the UI test runner.

```text
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = 92X872A57T
#include? "Local.xcconfig"
```

The identity is checked in on purpose. macOS ties permission grants to a program's code signature,
and ad-hoc signing makes a new signature on every build, so each build is a new program and every
grant is asked again mid-run: the UI runner's automation dialog, Screen Recording, and access to the
external volume (a real-data host stuck in `open()` while a shell lists the same path at once).
Deriving the identity per machine was tried and reverted: it fails the same way when the derivation
comes up empty, and it depends on machine state the repository cannot check.

A machine without the certificate, and CI, override on the command line, which beats every xcconfig:

```sh
make test-unit XCODEBUILD_FLAGS='CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='
```

A hand-written, gitignored `Config/Build/Local.xcconfig` is the lasting form; the `#include?` picks
it up. Check a build with `codesign -dv --verbose=2 <bundle>`: `Authority=Apple Development: ...`
with a `TeamIdentifier` is right, and `Signature=adhoc` causes repeated prompts.

## Output and transcripts

`tools/xcodebuild-run.sh` takes a log name and a full xcodebuild command. It writes the whole
transcript to `logs/<name>/<UTC timestamp>/<name>.log` and prints only diagnostics, tests that did not
pass, and the closing status line. xcodebuild repeats each diagnostic several times, with colour codes
and absolute paths. The filter strips both, prints each line once, and stops after
`OPENSKY_MAX_ERRORS` errors. The first screen of a failed build is then the whole answer, and nobody
has to grep the transcript. A failing run where no line matched the filter prints the last 40
transcript lines instead. `xcodebuild -quiet` cannot do this: it decides what to print before the text
exists, keeps no full copy, and drops `** TEST SUCCEEDED **`. Where transcripts go and how they age
out is on the [run output](/tools/run-output.md) page.

### Stale module copies

xcodebuild sometimes keeps an old copy of a package module in `Build/Products/<config>/` after an
interface change, while the compiler has emitted the new one under `Build/Intermediates.noindex/`.
Every module above it then fails with "cannot find in scope", "has no member", or "extra argument",
and a clean rebuild does not help ([environment](/tools/environment.md)). After a healthy build the
two files are identical, so `tools/stale-modules.sh` treats any difference as stale and deletes the
copy. A failed build stops at one module layer, so the modules above a stale copy are not emitted
again, and their own stale copies would show only after the next pass. So the script also deletes the
copy of every module whose emit-module dependency file (`<Module>-primary-emit-module.d`) names a
stale copy, and repeats until no new module is added. One more build then rebuilds all layers
together. `tools/xcodebuild-run.sh` runs it before every build, in the tree named by the build's
`-derivedDataPath`, so the index tree of `make health` is checked too. When a build fails and
leaves new stale copies, it deletes them and builds again, `OPENSKY_STALE_RETRIES` times
(default 1). Every command line also passes `-IDEBuildingContinueBuildingAfterErrors=YES`, so a
failed pass still emits the modules the failing one does not block, and fewer stale copies are
left for the next pass. No new pass starts after `OPENSKY_RETRY_MINUTES` (default 15). A failed
build that finds no new stale copies has a real error, so it stops at once. Before each new pass
it deletes the `-resultBundlePath` bundle that the failed pass wrote, because xcodebuild refuses
a path that exists. A test run without building skips all of this.

## Warnings are errors

`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` is in `Config/Build/Base.xcconfig`, next to
`MTL_TREAT_WARNINGS_AS_ERRORS`, so it covers every target. SwiftLint never sees compiler warnings,
and before this setting the test targets had gathered about a hundred. Expect a toolchain upgrade that
adds a deprecation warning to break the build. Fix the warning. Do not turn the setting off.

## Products path

For a macOS scheme built with `-derivedDataPath`, the products are always in
`$(DERIVED_DATA)/Build/Products/$(CONFIG)`. The `Makefile` computes it as `PRODUCTS`, and scripts call
`xcodebuild_products_dir CONFIG` from `tools/xcodebuild-lib.sh`, instead of paying seconds for
`xcodebuild -showBuildSettings`. This holds because every target builds for macOS only.

`tools/xcodebuild-lib.sh` is sourced, never run. It sets `OPENSKY_DERIVED_DATA` for a script run
outside `make`, and provides the products path and the output filter. The test targets share the
normal cache, except `make test-real PERF=1`, which changes a build setting and so builds into
`$OPENSKY_DERIVED_DATA-optimized`. Both stay on the external volume, and `make prune` removes both
from a removed worktree.

Two `xcodebuild` runs against the same derived-data folder deadlock until the tool times out. Let one
finish before starting another.
