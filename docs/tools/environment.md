---
type: Reference
title: Local environment and external state
description: Machine-specific and third-party facts that skills and AGENTS.md must not
  hardcode - permissions, upstream spec hosts, and Xcode and macOS quirks - each with its
  workaround and the condition that retires it.
tags: [environment, tooling, ci, gotchas]
---

# Local environment and external state

This page holds facts that are true of this machine or the outside world now, not of the
repository. Skills and `AGENTS.md` state lasting rules and link here.

Each entry states the current state, the workaround, the date it was last checked, and the
condition that retires it. An entry whose condition is met is deleted.

## This machine

### Game data

Checked 2026-11-01. The install is under `/Volumes/data/steam/steamapps/common/Skyrim Special
Edition/`. The game has never run on this Mac, so:

- There is no `plugins.txt` and no `~/Library/Application Support/Skyrim Special Edition/`.
  Every [load order](/formats/plugins-txt.md) takes the vanilla fallback. A probe of a modded
  load order needs a hand-made file named by `OPENSKY_PLUGINS_TXT`.
- There is no `.ess` save in the macOS documents folder. Checked 2026-11-02: 13 saves of
  the reference game, at player levels 1, 9, and 17, are in the Wine prefix under
  `/Volumes/data/opensky-reference-game/drive_c/users/<user>/Documents/My Games/Skyrim
  Special Edition/Saves/`. Set `OPENSKY_SKYRIM_SAVES` to that folder and run
  `make test PLAN=RealData` to run `ESSRealDataTests`.

Retires when a `plugins.txt` appears in a searched location.

### Permission grants

UI tests need Automation Mode, and XCTest turns it on at the start of each UI run. If the Mac
asks for a password, nobody answers, and the run times out with "Timed out while enabling
automation mode". Run this once per machine to drop the password:

```sh
sudo automationmodetool enable-automationmode-without-authentication
```

`automationmodetool` without arguments shows the setting, and `make check-perms` fails while the
password is still required.

A grant belongs to the built product, not the terminal. It lasts only while the product keeps
one code signature, which is why signing names a real identity
([build system](/tools/build-system.md#signing)):

| Grant | Goes to |
| --- | --- |
| Accessibility | `OpenSkyUITests-Runner.app` |
| File access (a removable volume, because the build cache is on an external disk) | `OpenSky.app` |
| Removable-volume access for package test targets | The plain `xctest` runner |

A grant cannot be scripted: TCC is protected by SIP, and the Accessibility entry is in the
root-owned system database. `make check-perms` checks what it can (the data root is readable,
and both bundles have a real signature) and opens the right settings pane for the rest. A
machine without the `xctest` grant shows a dialog on its first unit run, and the run waits
until it times out with "timed out while preparing"; click Allow once.

### Second display

Checked 2026-10-04 on macOS 27.0.1, with a second display above the main one. The app window
opens at a negative y position, on the second display, and `testCapturesRenderedFrame` fails
with `Failed to get screenshot: Failed to create screenshot. Image creation failed.`

Retires when the test passes with this display arrangement.

### Reference game toolchain

Checked 2026-10-28 ([reference game](/tools/reference-game.md),
[bridge plugin](/decisions/reference-bridge.md)):

- The Game Porting Toolkit Wine (the gcenx cask, Wine 7.7) cannot run the current Windows
  Steam: Steam crashes in `bcrypt` on the `BCRYPT_RNG_ALG_HANDLE` pseudo-handle. Plain Wine
  11.0 with the soju recipe runs it.
- `steamcmd` logs in under Wine 11, but the game rejects it and restarts through
  `steam://run/489830`.
- DXMT v0.80 aborts Skyrim at startup (DXMT issue #231). The fix is only on DXMT's main
  branch, so the reference game uses DXVK-macOS 1.10.3.
- The reference copy runs game version 1.7.104 (Steam build 24914197); the OpenSky install
  is build 13189953. SKSE 2.3.1 supports 1.7.104, but its download and the Address Library
  for it are on Nexus only, behind a login.
- CommonLibSSE-NG's `v15.0.1` clang-cl bundle needs clang-cl 22, so the bridge build uses
  Homebrew's `llvm@22`. xwin needs `--manifest-version 18` for MSVC 14.51; it logs checksum
  mismatches for a few Windows SDK packages and still completes.
- The Steam installer writes `Steam.exe` with a capital S; the case-insensitive volume finds
  it as `steam.exe`. Installing Rosetta 2 needs an administrator password.

Retires per item: a DXMT release runs Skyrim, the Game Porting Toolkit runs the current Steam,
SKSE and the Address Library have a download without a login, or the bridge moves to another
library build.

### Periphery

Checked 2026-10-08. The cask in the `peripheryapp/periphery` tap does not install. The
`Index checks` CI job installs the core formula (`brew install periphery`). Homebrew marks that formula
deprecated, because the upstream repository is archived, and plans to disable it on
2027-08-12.

Retires when Periphery has a maintained install path again, or `make lint-index` moves to another
tool.

## Upstream spec hosts

Checked 2026-10-20. Read the wikis from the offline mirrors
([offline wikis](/tools/offline-wikis.md)); `make sync-wiki ARGS='--site ck'` and `make sync-wiki ARGS='--site uesp'` keep them
current.

| Host | State | Use instead |
| --- | --- | --- |
| `en.uesp.net` pages | WebFetch gets HTTP 403 | The mirror, or `curl -sL -A 'Mozilla/5.0' '<url>'` |
| `en.uesp.net/w/api.php` | Answers `curl` with JSON, `action=parse` included | Works |
| `ck.uesp.net/wiki/<Page>`, `skyrimck.uesp.net` | HTTP 403 or a Cloudflare page | The mirror, or `https://ck.uesp.net/w/api.php` |
| `www.creationkit.com` | A maintenance page for every path, Wayback snapshots included | `ck.uesp.net` |
| `TES5Edit/TES5Edit` on GitHub | The default branch is `dev-4.1.6`; raw URLs on another branch return 404 | Check with `gh api repos/TES5Edit/TES5Edit` |

For a Papyrus signature, the install's own compiled script is the better source
([actor natives](/engine/papyrus-actor-natives.md)).

Retires per host when it changes behaviour.

## Xcode and macOS

### Builds

| Symptom | Cause and workaround | Retires when |
| --- | --- | --- |
| `Virtual filesystem overlay file '.../all-product-headers.yaml' not found` in `make build-app` | A package test builds the same checkout at the same time. Run them one after the other | An overlapping build passes (checked 2026-10-24, Xcode 27) |
| `DVTAssertInvalidatableObjectIsValid` in `IDESwiftPackageBuildable.blueprint` before any test runs | The build before failed and removed the `OpenSky` driver records. Run `make test` again | A failed build is no longer followed by it (checked 2026-10-28, Xcode 27) |
| `ValidateCAS` fails with `CAS validation requires exclusive access but CAS was in use` | Another checkout's build used the shared compilation cache store while this build validated it. Build again | A build validates the store while another build uses it (checked 2026-11-07, Xcode 27.2) |
| `invalid or unsupported format for signature` naming a `.cstemp` file | A build stopped during `codesign`. Run `find "$OPENSKY_DERIVED_DATA/Build/Products" -name '*.cstemp' -delete` and build again. `make test-package` keeps its products in `.build/out/Products`; a failed compile there leaves them too, and the next run fails on `libOpenSkyTestSupport.a` | Xcode cleans its own signing temp files (checked 2026-10-04) |
| `EXC_BAD_ACCESS` after a protocol or struct change | The incremental build does not recompile callers when a requirement is added mid-protocol, or a stored property is added to a struct another file stores. Add requirements at the end, or touch the callers. A clean CI build is not affected | The driver tracks layout changes (checked 2026-10-11, Xcode 27.0) |

### A failed compile skips the files that depend on it

Checked 2026-10-17 on Xcode 27.1, Swift 6.4. When a build changes a type's layout and fails in
another file, the driver logs `not scheduling dependents of <file>; unknown changes`. The next
build compiles only the fixed file, so the dependents keep old field offsets and crash with
`EXC_BAD_ACCESS`. `tools/failed-build-records.sh` works around it
([build system](/tools/build-system.md#driver-records-after-a-failed-build)).

Retires when the driver keeps skipped dependents in its record after a failed job: the
reproduction then passes without the script's call in `tools/xcodebuild.sh`.

### A compilation cache hit leaves the driver record dirty

Checked 2026-10-05 on Xcode 27.0. swift-build returns `.succeeded` for a compile job that the
compilation cache replays, without calling `jobFinished` (`SwiftDriverJobTaskAction.swift` in
[swift-build](https://github.com/swiftlang/swift-build)). The driver then marks each such file
`needsNonCascadingBuild` in `<Module>-primary.priors`, and compiles it again, from the cache,
each time it plans the module.

The driver plans a module again when its planning task's signature changes, such as between
schemes or between build variants. So `make build-tests` builds the CLI through the `OpenSky`
scheme, and the scheme builds `OpenSkyTests` for testing in every plan, which keeps the
dynamic variants the same between plans.

To see the driver's reasons, export `ADDITIONAL_SWIFT_DRIVER_FLAGS=-driver-show-incremental`
before a build; the same flag in `OTHER_SWIFT_FLAGS` does nothing.

Retires when swift-build reports a replayed job to the driver: `make build-cli` followed by
`make test` then compiles no Swift file.

### Package framework variants warn about declared dependencies

Checked 2026-10-01 on Xcode 27.0. A unit build prints lines like `warning: 'OpenSkyFormatsESM'
is missing a dependency on 'OpenSkyFormatsCore'`, although `src/Package.swift` declares it. A test
bundle links each engine target again, so Xcode builds it as a dynamic variant, and Swift
Build's `DIAGNOSE_MISSING_TARGET_DEPENDENCIES` finds no edge from a variant. Fixed upstream in
[swift-build PR 1457](https://github.com/swiftlang/swift-build/pull/1457).

`src/config/Build/Overrides.xcconfig` turns the check off where `MACH_O_TYPE` is `mh_dylib`. The
imports are still checked by `tools/lint/module-graph.sh`.

Retires when the installed Xcode ships that fix: delete the override, and a clean
`make build-tests` prints no `is missing a dependency on` line.

### Tests

| Symptom | Cause and workaround | Retires when |
| --- | --- | --- |
| A test host hangs at idle, with nothing in the result bundle | `AVAudioPlayerNode.playerTime(forNodeTime:)` hangs under `.offline` manual rendering. The playback position is counted from `manualRenderingSampleTime` instead ([audio](/engine/audio.md)) | The query answers under offline rendering (checked 2026-08-10, Xcode 26.6) |
| `The test runner hung before establishing connection`, or a real-data run that runs 0 tests with no error | A days-old `testmanagerd` stalls. Check its start with `ps -eo pid,lstart,command \| grep testmanagerd` and `kill -9` it; `launchd` starts a new one. It is shared, so check for other running tests first | A fresh daemon stops going stale (checked 2026-10-18) |
| MetalFX tests wait out their allowance | `ANECompilerService` can stop answering for hours, and MetalFX builds its temporal scaler through it. The renderer builds scalers off the main actor ([upscaling](/rendering/upscaling.md#building-the-scaler)), and `MetalFXCompilerProbe` fails the tests early with a clear message | MetalFX builds its scalers without the Neural Engine (checked 2026-10-13) |
| A real-data test uses tens of GB and locks the machine | Wrap heavy real-data runs in `tools/memguard.sh` ([testing](/testing.md#memory-watchdog)) | The tests carry their own bounds (checked 2026-07-20) |
| `xccov` reports no package file, only `OpenSky.app` with 0 files | Package modules build into frameworks the result bundle does not list as coverage products. `tools/coverage/` reads the profile with `llvm-cov` instead ([test runs](/tools/test-runs.md#code-coverage)) | `xccov view --report` lists the package frameworks (checked 2026-11-09, Xcode 27.2) |
| `xcrun xctrace record --launch -- openskycli ...` never starts the process | Start the process first and attach with `--attach <pid>`. `tools/profile.sh` does this ([profiling](/testing.md#profiling)) | A `--launch` recording of the CLI completes (checked 2026-10-01, xctrace 27.0) |

### Test plans and Swift Testing

Checked 2026-10-13 on Xcode 27.0:

- A plan's `environmentVariableEntries` reach the unit-test host; a plain `xcodebuild test`
  environment variable does not.
- A plan's environment value is not macro-expanded: `$(OPENSKY_DATA_ROOT)` arrives as that
  literal string. So a plan holds literal paths, and nothing in the environment can override
  one.
- A plan's `selectedTests` and `skippedTests` do not match Swift Testing tests: a plan that
  selects any runs zero tests, and a plan that skips one skips nothing. Command-line
  `-only-testing` works, and so does selecting a whole target.
- A plan's `skippedTags` skips nothing, but `selectedTags` works. So `Quick` skips through
  the environment variable `OPENSKY_SKIPPED_TAGS` and a condition trait
  ([test runs](/tools/test-runs.md#tags)).

Retires when Xcode matches plan selection and `skippedTags` against Swift Testing tests.
