---
type: Tool
title: Build system and xcodebuild invocation
description: How make and the tools/ scripts share one xcodebuild invocation - the make targets, the
  src/config/ xcconfig layer, the OpenSkyShaderTypes module, compilation caching across worktrees,
  signing, the output summary, warnings as errors, and the products path.
tags: [tool, build, make, xcodebuild]
---

# Build system and xcodebuild invocation

`make` is the one entry point, and `make help` lists every target and option. A recipe is one
command: the logic lives in a script under `tools/` that takes arguments, so a script can be run and
tested on its own. Each script that compiles, tests, or installs calls `tools/xcodebuild.sh`, which
adds the shared part of the command line, so the cache location and the output cannot drift apart
per target.

## The shared invocation

`tools/xcodebuild.sh NAME ARGS...` runs `xcodebuild ARGS...` with:

- `-workspace src/OpenSky.xcworkspace` and `-derivedDataPath`, this checkout's build tree;
- `COMPILATION_CACHE_CAS_PATH` and `SDK_EXPLICIT_MODULES_OUTPUT_PATH`, shared by every tree;
- `-IDEBuildingContinueBuildingAfterErrors=YES` ([below](#stale-module-copies));
- `CLANG_COVERAGE_MAPPING=YES` for Debug ([test runs](/tools/test-runs.md#code-coverage)) and
  `ARCHS=arm64` for Release, because `Float16` does not exist on x86_64;
- `XCODEBUILD_FLAGS`, and a result bundle in the run directory.

`tools/build-env.sh` names the paths, for the scripts and for `make`: `OPENSKY_DERIVED_DATA`,
`OPENSKY_COMPILATION_CACHE`, `OPENSKY_SDK_MODULES`, and `XCODE_XCCONFIG_FILE`. CI sets the first
three itself. `tools/build.sh` builds the app, the CLI, a plan's test bundles, or the installed
app, and `tools/test.sh` runs a plan.

The options are variables with one meaning everywhere: `PLAN`, `CONFIG`, `T`, `N`, `COVERAGE`,
`SAN`, `CAP`, `DIFF_BASE`, `ARGS` (the script's own arguments), and `XCODEBUILD_FLAGS`. Any other
variable on the command line fails the run with the list.

### The tooling, before and after

Measured with `git ls-tree` on 2026-11-09, on `main` before the change and on the change:

| Part | Before | After | Why it is not smaller |
| --- | --- | --- | --- |
| Make files | 3 files, 679 lines | 1 file, 168 lines | |
| Make targets | 97, 35 in `make help` | 33, all in `make help` | |
| `make help` | 95 lines with `ALL=1` | 61 lines | |
| Scripts in `tools/` | 40 files, 3,618 lines | 44 files, 3,175 lines | The logic of the old recipes moved into scripts |
| Checks: lint, format, coverage | 29 files, 2,900 lines | 42 files, 3,269 lines | One script per check, from the old recipes, and a self-check in every lint |
| Test plans | 13 files, 3,937 lines | 9 files, 1,342 lines | [Test runs](/tools/test-runs.md#test-plans) gives each plan's reason |
| Workflows | 633 lines | 604 lines | Each job still installs its tools |
| Custom SwiftLint rules | 19 | 19 | Each is a project rule SwiftLint does not ship |
| `make check`, no changes | 24 s | 14 s, with every self-check | |

What went, and why Xcode or plain behaviour replaces it:

- The two-builds-at-a-time slots and the per-tree locks. Two builds into one tree still collide in
  xcodebuild's build database, so start a second build only after the first ends.
- The cache budget and the seeding of a new tree from the newest one. `make prune` deletes the trees
  of removed worktrees; a new tree builds from the shared compilation cache.
- The phase timing. The result bundle holds the build and test times.
- The stale-module retry ([below](#stale-module-copies)) and the cleanup of test bundles left
  unsigned by a stopped build. A build that then fails `CodeSign` with "code object is not signed
  at all" needs `make clean`.
- The log filter. The summary comes from the result bundle ([below](#output-and-transcripts)).
- The coverage computation stays: `xccov` reports no package file ([test
  runs](/tools/test-runs.md#code-coverage)).
- The module-graph check stays. It reads the declared graph from the manifest, not the imports,
  and checks rules a manifest cannot state, such as layers.

### The workspace and the start-up scan

`src/OpenSky.xcworkspace` holds the project and, as a folder, the package in `src/`. Only
that folder reference puts the package test targets into a test plan's build: through
`-project src/OpenSky.xcodeproj`, or a workspace that names `src/Package.swift` instead of the folder,
`build-for-testing` succeeds and writes an `.xctestrun` with no package test bundle in it
(measured 2026-10-05). So every command line uses the workspace.

The folder reference has a price. At every start, before it resolves the package graph, Xcode's
package watcher (`SPMPackageDirectoryStructureFileSystemWatcher` in a `sample` of xcodebuild) reads
every entry under the package folder. It skips only entries named `.git`, `.swiftpm`, or `.build`,
at any depth. It does not follow a symlink. Hidden names such as `.cache` or `.claude` are read
like any other. No setting adds a name to that list.

So the package sits in `src/`, and everything that grows stays outside it at the repository root:
the build cache in `.cache/`, run output in `.logs/`, and Claude Code's worktrees in
`.claude/worktrees/`. Inside `src/` only `.build/` (SwiftPM's own output) and the small
`src/.vendor/` grow. Measured on 2026-11-08: with the package at the repository root, the main
checkout held 142 linked worktrees (about 7.4 million files) and 141 GB of build trees, and
`xcodebuild -list` took 154 s there against 7 s in a worktree.

The build trees live in the main checkout's hidden `.cache/Build/`, on the data volume, and the
internal disk holds only the app's asset cache. About twenty worktrees are alive at once, and each
tree is 1.5 to 8 GB, so the trees filled the internal disk. The data volume is a USB disk that
writes at about 135 MB/s against the internal disk's 2 GB/s. Measured on 2026-10-18, a fresh Debug
`make build-app` there took 84 to 126 s when every task hit the
[compilation cache](#compilation-caching).

## Build trees

`tools/build-env.sh` names one tree per checkout, `.cache/Build/<checkout folder>`, in the main
checkout. `make clean` removes this checkout's tree, and `make prune` the trees of removed
worktrees. CI keeps its tree inside its workspace.

What each tree holds, measured on 2026-10-18:

| Part | Size | Shared? |
| --- | --- | --- |
| `Build/` (objects, products, build database) | 1.2 GB | No: a cache hit still writes a full copy, never an APFS clone |
| `ModuleCache.noindex` (dependency scanner) | 470 MB | No: the hashes differ per checkout |
| SDK precompiled modules | 230 MB | Yes: `OPENSKY_SDK_MODULES`, `.cache/SDKModules.noindex` |
| `SourcePackages` | 50 MB | No: about 40 dependency tasks miss per new tree, which costs seconds |

## Build settings in src/config/

Every build setting is in a text file under `src/config/Build/`. The project file has empty
`buildSettings` and names these files as bases. So a setting change is a one-line diff a review can
read, and the project file, the worst merge conflict surface, holds no copies of the values.

```text
src/config/
├── Build/
│   ├── Base.xcconfig        deployment target, SDK, Swift mode, warnings, versioning
│   ├── Debug.xcconfig       #include Base + -Onone, dwarf, testability
│   ├── Release.xcconfig     #include Base + wholemodule, dSYM, VALIDATE_PRODUCT
│   ├── Signing.xcconfig     CODE_SIGN_IDENTITY and DEVELOPMENT_TEAM, one identity
│   ├── App.xcconfig         OpenSky: bundle id, Info.plist keys, ffmpeg + astcenc link
│   ├── CLI.xcconfig         OpenSkyCLI: binary name, isolation default, ffmpeg + astcenc link
│   ├── Tests.xcconfig       the unit bundles: TEST_HOST, BUNDLE_LOADER
│   ├── UITests.xcconfig     OpenSkyUITests: TEST_TARGET_NAME
│   └── Overrides.xcconfig   above every target, package targets too
└── TestPlans/
    └── *.xctestplan         the nine test plans (see test runs)
```

The test plans are in `src/config/TestPlans/` for the same reason ([test runs](/tools/test-runs.md)).
`Debug.xcconfig` and `Release.xcconfig` are the project's base configurations for every target. The
target files sit above them and apply to both configurations of one target. Only a setting that
differs per configuration inside one target still belongs in the project file.

The project's files never reach a package target, whose settings come from `src/Package.swift`.
`Overrides.xcconfig` is the one place for a setting that has to: `tools/build-env.sh` exports
`XCODE_XCCONFIG_FILE` pointing at it, and xcodebuild applies that
file above every target in the build. A build started from the Xcode window does not read it. It
turns off a missing-dependency check that is wrong for package framework variants
([environment](/tools/environment.md#package-framework-variants-warn-about-declared-dependencies)).
It also holds the prefix-mapping settings and `SWIFT_PACKAGE_NAME`, which keep the shared
compilation cache key the same in every worktree (see below).

`tools/lint/swift-baseline.sh` reads `SWIFT_VERSION` from `src/config/Build/*.xcconfig` and the project
file, so the Swift 6 mode check still catches a configuration that slips back
([Swift toolchain](/tools/swift-toolchain.md)).

## The OpenSkyShaderTypes module

Structs and constants shared by Swift and the Metal shaders live in
`src/Sources/OpenSkyShaderTypes/ShaderTypes.h`, next to a `module.modulemap` that declares
`module OpenSkyShaderTypes { header "ShaderTypes.h" export * }`. The folder is a clang target of the
Swift package, so a file that writes `import OpenSkyShaderTypes` sees the types and no other file
does. SwiftPM links a clang target's object file, so the target also holds `ShaderTypes.m`, which
declares nothing. It is Objective-C because the header imports Foundation.
The shaders reach the header by a relative path, `../OpenSkyShaderTypes/ShaderTypes.h`, because
a package target's Metal compile takes no header search path
([shader library](/decisions/shader-library.md)).

There is no bridging header. A bridging header is visible to every Swift file in its target, so every
file depended on the shared header whether it used it or not, and `OpenSkyCLI` had to name the app's
header by path. The header also pulls in Foundation and `simd`, so files that relied on that now
import them themselves, as `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` asks. The module did
not make incremental builds smaller. Editing the header and editing an unrelated
parser file both recompile the whole target, because the module-wide `.swiftmodule` is an input to
every compile task. The reason for the module is explicit dependencies and two decoupled targets.

## Compilation caching

`COMPILATION_CACHE_ENABLE_CACHING = YES` in `src/config/Build/Base.xcconfig` turns on Xcode 26's compilation
cache. Each compile task is keyed on its command line and inputs, and a task with a known key
replays the stored result instead of compiling. Explicit modules, which the cache needs, are already
on by default. The store is `$(COMPILATION_CACHE)`, passed as `COMPILATION_CACHE_CAS_PATH` on every
command line, so every checkout and every tree uses one store.
`make clean` keeps it; `make clean ARGS=--deep` removes it.

What it helps and what it does not:

- It helps a rebuild of a state compiled before, after the build folder is gone. In Debug that was
  about four and a half times faster. In Release, which compiles the module as one task, it was half
  a minute instead of thirteen.
- A branch switch gains nothing: switching in place keeps `Build/` in the cache, so the build
  system's own incremental state decides.
- A cache hit leaves the Swift driver's incremental record saying "needs build"
  ([environment](/tools/environment.md#a-compilation-cache-hit-leaves-the-driver-record-dirty)).
  Each switch between build contexts, such as `make build-cli` then `make test`, then
  compiles those modules again and relinks everything above them. So the `OpenSky` scheme
  builds `openskycli` for testing, and the Debug `make build-app` and `make build-cli` use
  `build-for-testing` on the `AgentControl` plan, so every Debug build is the test context.
- An ordinary edit-and-build loop is unaffected. Apple describes the feature as being for rebuilding
  states compiled before.

Each transcript ends its build with a `CompilationCacheMetrics` line: hits out of cacheable tasks.
`COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES` in `XCODEBUILD_FLAGS` also prints each task's key
and each miss. It is not checked in, because it adds lines to every transcript.

The store grows to tens of gigabytes. It prunes itself in generations: on 2026-10-18 a new
`builtin/v1.2/` folder started next to the 91 GB `v1.1/`, and each hit copied its entry into the
new folder. `COMPILATION_CACHE_LIMIT_SIZE` set below the store's size shrank nothing at once.
`make clean ARGS=--deep` removes it. CI starts its
store over by size instead ([CI](/tools/ci.md#caches)).

### One store for every worktree

A task's key holds its whole command line, so any path or name that differs per checkout or per
tree makes every other worktree miss. Two inputs did that:

- Absolute paths. `src/config/Build/Overrides.xcconfig` sets `SWIFT_ENABLE_PREFIX_MAPPING`,
  `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, `CLANG_ENABLE_PREFIX_MAPPING`, and
  `CLANG_ENABLE_PROJECT_PREFIX_MAPPING` for every local build, Debug and Release. Xcode then
  rewrites the package folder `src/` to
  `/^src`, derived-data temporaries to `/^derived`, and products to `/^built`. The settings must
  be in that file: a project `.xcconfig` does not reach the package targets, which hold the engine.
- The package name. SwiftPM passes the checkout folder's name to every compile as `-package-name`.
  `SWIFT_PACKAGE_NAME = opensky` fixes it, and only widens `package` access in the dependencies.

`llvm-cas --diff-graphs <key> <key>` on two keys of one task shows the input that differs.
Measured on 2026-10-18 with both in place, a Debug `make build-app` from a second checkout into a
fresh tree hit 647 of 688 tasks; before, it hit 12. Every checkout passes the same store path, the main
checkout's. `tools/link-shared.sh`, run by the vendored libraries' file targets, links a
worktree's `src/.vendor` to the main checkout's. It lives inside the
package folder so that prefix mapping covers its header paths too.

### A live check after a one-file change

Live checks run Release, because a Debug build plays too slowly. With the mapping on for Release
too, a new checkout with an empty tree built the Release CLI in 59 s (87 of 93 hits) and the app in
44 s (80 of 84); after a one-file change, 47 s and 33 s. Before, it hit 0 and took 5 to 11 minutes.
The misses are the two dependency packages, whose checkouts sit inside each tree. Run directories,
2026-11-09, in the main checkout: `.logs/build-cli/20261109T003935Z`,
`.logs/build-app/20261109T004107Z`, `.logs/build-app/20261109T004151Z`,
`.logs/build-cli/20261109T004224Z`. The build that ships passes `OPENSKY_PREFIX_MAPPING=NO`
(`preview.yml`), so its dSYM names the real source paths.

The mapping has three costs:

- A replayed task writes no index data. Periphery reads the index, so `make lint-index` builds
  uncached into the `-index` cache tree ([code-health automation](/decisions/code-health-automation.md)).
- `#filePath` reads `/^src/...`, so a test cannot find the checkout from it. The build cache is
  outside the checkout too, so `make test PLAN=RealData` passes the checkout to the test process as
  `TEST_RUNNER_OPENSKY_CHECKOUT`, and real-data suites write into its `.logs/`.
- Debug info names sources `/^src/...`. A command-line `lldb` needs
  `settings set target.source-map /^src <checkout>/src`.

## Signing

`src/config/Build/Signing.xcconfig` names the identity and team, and every target that makes a bundle
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
make test XCODEBUILD_FLAGS='CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='
```

A hand-written, gitignored `src/config/Build/Local.xcconfig` is the lasting form; the `#include?` picks
it up. Check a build with `codesign -dv --verbose=2 <bundle>`: `Authority=Apple Development: ...`
with a `TeamIdentifier` is right, and `Signature=adhoc` causes repeated prompts.

## Output and transcripts

`tools/xcodebuild.sh` writes the whole transcript and the result bundle into
`.logs/<name>/<UTC timestamp>/`, and prints only what the bundle holds, through
`tools/xcresult_summary.py`: each error and warning once with its file and line, then the failed
tests with their messages and the test totals. `xcresulttool get build-results` and `get
test-results summary` hold both, so no filter parses the transcript. A failed run with no bundle
prints the last 40 transcript lines. Where run directories go and how they age out is on the [run
output](/tools/run-output.md) page.

### Stale module copies

The compiler emits a package module's `.swiftmodule` under `Build/Intermediates.noindex/` without
type-checking function bodies, and a separate copy task puts it in `Build/Products/<config>/`, where
the modules above read it. So a module whose public interface changed emits fine even when one of
its own files no longer compiles, and a build that stops at the first error cancels the copy task
queued behind the emit. Products then keeps the old module while Intermediates holds the new one,
and every module above fails with "cannot find in scope", "has no member", or "extra argument"
until something rewrites the copy. Reproduced on 2026-10-05 by renaming a public `BinaryReader`
method: with `-IDEBuildingContinueBuildingAfterErrors=NO`, the failed build left the copy of
`OpenSkyFormatsESM` stale; with `YES`, the same build ran the copy task and left Products
consistent. Every command line therefore passes `YES`, so a failed build still writes every module
that did emit.

A script that deleted stale copies after each build was removed with the build wrapper; the flag
covers the case it was written for. A build that fails with those errors right after an interface
change in a lower module is worth a `bug` issue with the transcript.

### Driver records after a failed build

The Swift driver compiles a target in waves. The first wave holds the changed files. When a
file's declarations change, a second wave compiles the files that use them. After a failed
compile job the driver starts no second wave, but it still saves the new dependency graph in
`<Target>-primary.priors`. The next build then thinks those files are current and links their
old objects. In a final class or a struct, every file reads a stored property at a fixed
offset. So an old object reads the wrong field and crashes with `EXC_BAD_ACCESS`
([environment](/tools/environment.md#a-failed-compile-skips-the-files-that-depend-on-it)).

So after every failed build, `tools/failed-build-records.sh` reads the transcript and deletes
the record of each target with a failed compile. The target is the folder of the failed file
below `src/Sources/` or `src/Tests/`. A target without its record is compiled whole in the next
build. `tools/xcodebuild.sh` does this for xcodebuild, in the tree's `Build/`.
`make compile` and `make test-package` do it for `swift build`, in `.build/out`. The cost
is one full compile of each failed target, and only after a failure.

## Warnings are errors

`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` is in `src/config/Build/Base.xcconfig`, next to
`MTL_TREAT_WARNINGS_AS_ERRORS`, so it covers every target. SwiftLint never sees compiler warnings,
and before this setting the test targets had gathered about a hundred. Expect a toolchain upgrade that
adds a deprecation warning to break the build. Fix the warning. Do not turn the setting off.

## Products path

For a macOS scheme built with `-derivedDataPath`, the products are always in
`<tree>/Build/Products/<CONFIG>`, so make and the scripts compute the path instead of paying seconds
for `xcodebuild -showBuildSettings`. This holds because every target builds for macOS only.
`make test PLAN=Perf` changes a build setting and so builds into `<tree>-optimized`, and
`make lint-index` into `<tree>-index`. `make clean` and `make prune` cover all three.

Two `xcodebuild` runs against the same derived-data folder deadlock until the tool times out. Let one
finish before starting another.
