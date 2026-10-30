---
type: Reference
title: Local environment and external state
description: Dated record of machine-specific and third-party facts that skills and AGENTS.md must
  not hardcode - permissions, upstream spec host quirks, and xcodebuild behaviors -
  each with the condition that retires it.
tags: [environment, tooling, ci, gotchas]
---

# Local environment and external state

This page holds facts that are true of this machine or the outside world right now, not of the
repository. Skills and `AGENTS.md` state lasting rules and link here. They do not keep copies,
because a copy has no date and nobody notices when it expires.

Every entry has the date it was observed and the condition that retires it. An entry whose
condition is met is deleted, not changed.

## AVAudioPlayerNode.playerTime hangs offline rendering

Observed 2026-08-10 on Xcode 26.6 and macOS 26.5.2. Calling `AVAudioPlayerNode.playerTime(forNodeTime:)`,
or reaching it through `lastRenderTime`, on a node attached to an `AVAudioEngine` in `.offline`
manual rendering mode hangs the app-hosted test host. The process stops running tests and sits idle,
and `xcodebuild` waits until it is killed. Nothing reaches the result bundle, so it looks like an
endless test, not a failure. Every suite that reached the query hung, which is what showed the API
was at fault and not the caller.

So the playback position is counted from `manualRenderingSampleTime` instead of a node time query
([audio](/engine/audio.md)). Anything else that needs a sample-exact output position has to solve
this first.

Retires when a later macOS or Xcode answers the query under offline rendering.

## Missing VFS overlay when an app build overlaps a package test

Observed 2026-10-24 on Xcode 27. `make build-app` failed with `Virtual filesystem overlay file
'.../all-product-headers.yaml' not found` while `make test-package` was building the same
checkout. The same `make build-app` passed when run again on its own. Run them one after the
other in one checkout.

Retires when an app build that overlaps a package test in the same checkout passes.

## xcodebuild asserts before the unit tests start

Observed 2026-10-28 on Xcode 27. `make test-unit` built every target, then `xcodebuild` stopped
with `DVTAssertInvalidatableObjectIsValid` in `IDESwiftPackageBuildable.blueprint`, before any test
ran. A failed build in the run just before had removed the `OpenSky` driver records. The same
`make test-unit` passed when run again.

Retires when a failed build is no longer followed by this assertion.

## Upstream spec hosts

Quirks that cost time in every format parser session. Each retires when the host changes behavior.

- Observed 2026-07-20: UESP (`en.uesp.net`, `ck.uesp.net`) answers the WebFetch tool with HTTP 403.
  Use `curl -sL -A 'Mozilla/5.0' '<url>'`.
- Observed 2026-10-20: the MediaWiki API at `https://en.uesp.net/w/api.php` answers `curl` with
  JSON, `action=parse` included. Read the `Skyrim:` and `Skyrim Mod:` pages from the offline mirror
  ([offline wikis](/tools/offline-wikis.md)); `make uesp-wiki` keeps it current.
- Observed 2026-07-20: the `TES5Edit/TES5Edit` default branch is `dev-4.1.6`, not `main` or `dev`.
  Raw file URLs return 404 on the wrong branch. Check with `gh api repos/TES5Edit/TES5Edit`.
- Observed 2026-09-08: `ck.uesp.net` answers a direct `curl` with a Cloudflare "Just a moment..."
  page, so the user agent trick no longer works there. Its Wayback snapshots still load
  (`https://web.archive.org/web/2023/https://ck.uesp.net/wiki/<Page>`). Pages the Wayback Machine
  never saved cannot be reached from here. For a Papyrus signature, the install's own compiled
  script is the better source anyway ([actor natives](/engine/papyrus-actor-natives.md)).
- Observed 2026-10-15: `ck.uesp.net/wiki/<Page>` answers `curl` with HTTP 403, but the MediaWiki
  API at `https://ck.uesp.net/w/api.php` answers with JSON, `action=parse` included. Read pages
  from the offline mirror ([offline wikis](/tools/offline-wikis.md)); `make ck-wiki` uses
  the API and falls back to the Wayback Machine.
- Observed 2026-10-09: `skyrimck.uesp.net` also answers `curl` with the Cloudflare page, and the
  Wayback Machine has no snapshot of `ck.uesp.net/wiki/Papyrus_INI_Settings`. A web search still
  returns the page's text in its summary.
- Observed 2026-08-07: `www.creationkit.com` serves a "down for backend maintenance" page for every
  path, and its Wayback snapshots redirect to that page. Use the `ck.uesp.net` snapshots above.

## No plugins.txt on this machine

Observed 2026-08-10. The install under `/Volumes/data/steam/steamapps/common/Skyrim Special
Edition/` has `Skyrim.ccc` and the ini files but no `plugins.txt`. There is no
`~/Library/Application Support/Skyrim Special Edition/`, and the Steam library has no `compatdata/`:
the game has never been launched here. So every [load order](/formats/plugins-txt.md) on this
machine takes the vanilla fallback, and the `plugins.txt` paths cannot be checked against a file the
game wrote. A probe of a modded load order needs a hand-made file named by `OPENSKY_PLUGINS_TXT`.

Retires when a `plugins.txt` appears in a searched location.

## Reference game toolchain

Observed 2026-10-25 on macOS 27.0.1 ([reference game](/tools/reference-game.md)):

- The Game Porting Toolkit Wine (the gcenx cask, Wine 7.7) cannot run the current Windows
  Steam: Steam crashes in `bcrypt` on the `BCRYPT_RNG_ALG_HANDLE` pseudo-handle.
- Plain Wine 11.0 runs Steam, but its window stays black and the client never logs on
  ("Failed to start auth session ... Transport Error"). The soju recipe fixes both.
- `steamcmd` logs in under Wine 11, but the game rejects it and restarts through
  `steam://run/489830`.
- DXMT v0.80 (April 2026) is the newest release and aborts Skyrim at startup (DXMT issue
  #231). The fix is only on DXMT's main branch, which needs DXMT's own Wine. The reference
  game uses DXVK-macOS 1.10.3 until a DXMT release has the fix.
- Steam updated the reference copy from build 13189953 (the OpenSky install) to 24914197
  before it would start the game; the update downloaded 1.6 GB.
- The Steam installer writes `Steam.exe` with a capital S; the case-insensitive volume
  finds it as `steam.exe`.
- Rosetta 2 needed an administrator password to install.

Retires when a DXMT release runs Skyrim, or the Game Porting Toolkit ships a Wine that
runs the current Steam.

## Reference game bridge downloads

Observed 2026-10-28 ([bridge plugin](/decisions/reference-bridge.md)):

- The reference copy runs game version 1.7.104 (Steam build 24914197). SKSE 2.3.1 supports
  it, but skse.silverlock.org links only to Nexus for that build, and GitHub's releases end
  at 2.2.6. The Address Library for 1.7.104 is on Nexus only too, behind a login.
- CommonLibSSE-NG's `v15.0.1` clang-cl bundle was built with clang-cl 22.1.3, so the
  build uses Homebrew's `llvm@22` (22.1.8) rather than the current `llvm` (23).
- xwin's default manifest gives MSVC 14.44, which lacks STL helpers the library calls;
  `--manifest-version 18` gives 14.51. xwin logs checksum mismatches for a few Windows SDK
  packages and still completes.

Retires when SKSE and the Address Library have a download without a login, or the bridge
build moves to another library build.

## Permission grants

UI tests need Automation Mode, and XCTest turns it on at the start of each UI run. If the Mac asks
for a password, nobody answers, and the run times out with "Timed out while enabling automation
mode". Run this once per machine to drop the password:

```sh
sudo automationmodetool enable-automationmode-without-authentication
```

`automationmodetool` without arguments shows the setting, and `make test-perms` fails while the
password is still required.

A grant belongs to the built product, not the terminal, and lasts only while the product keeps one
code signature, which is why signing names a real identity ([build system](/tools/build-system.md#signing)).
Accessibility goes to `OpenSkyUITests-Runner.app`. File access goes to `OpenSky.app`, which macOS
treats as a program on a removable volume when the build cache is on an external disk. The grant
cannot be scripted: TCC is protected by SIP, and the Accessibility entry is in the root-owned system
database. `make test-perms` checks what it can (the data root is readable, and both bundles have a
real signature) and opens the right settings pane for the rest.

Observed 2026-09-28. A test bundle without a test host runs in the plain `xctest` runner. macOS
asks that runner for removable-volume access, and the run waits on the dialog until it times out
with "timed out while preparing". Clicking Allow once let the run continue. The package test
targets run in that runner ([Swift modules](/tools/modules.md)), so a machine without the grant sees
the same dialog on its first unit run.

## UI test window screenshot fails on a second display

Observed 2026-10-04 on macOS 27.0.1, with a second display arranged above the main one.
`testCapturesRenderedFrame` failed with `Failed to get screenshot: Failed to create screenshot.
Image creation failed.` The app window opened at a negative y position, on the second display. The
other 31 UI tests passed in the same run.

Retires when the test passes with this display arrangement, or when the window opens on the main
display.

## Stale testmanagerd

Observed 2026-08-06. A days-old XCTest daemon can stall a fresh run at 0% CPU. The signs are
`The test runner hung before establishing connection` and
`Timed out after 120.0s while initiating control session with daemon`, in `make test-unit` and
`make test-real` alike. `killall testmanagerd` is not always enough, because a stuck daemon ignores
SIGTERM. Check its start date with `ps -eo pid,lstart,command | grep testmanagerd` and `kill -9` it
if it survived. `launchd` starts a new one on the next run.

Retires when a fresh daemon stops going stale over days.

Observed again 2026-10-18 with a different sign: with a one-day-old daemon, `make test-real T=...`
built and then ran 0 tests, an existing real-data suite included, with no error. The daemon is
shared with other sessions, so check for other running tests before killing it.

## xctrace --launch never starts the process

Observed 2026-10-01 on xctrace 27.0. `xcrun xctrace record --template 'Time Profiler' --launch --
openskycli ...` printed "Launching process" and then waited for more than ten minutes. The CLI sat
at 0% CPU with about 90 KB resident, so it never ran its first line. Starting the CLI first and
attaching with `--attach <pid>` recorded normally. `tools/profile.sh` lets `openskycli benchmark`
open the app, then attaches to the app's process
([profiling](/testing.md#profiling)).

Retires when a `--launch` recording of the CLI runs to completion.

## Memory watchdog for heavy real-data tests

Observed 2026-07-20. A runaway real-data test used about 30 GB of resident memory and locked the
machine. `tools/memguard.sh` caps resident size and must wrap heavy real-data runs
([testing](/testing.md#memory-watchdog)).

Retires when the tests carry their own bounds.

## Test plans, environment entries, and Swift Testing

Observed 2026-08-06 on Xcode 26.5 (build 25F70):

- A test plan's `environmentVariableEntries` reach the unit-test host. A plain `xcodebuild test`
  environment variable does not.
- A plan environment value is not macro-expanded. `$(OPENSKY_DATA_ROOT)` arrives at the host as that
  literal string, as read back from the generated `.xctestrun`. So a plan holds literal paths, and
  nothing in the environment can override one.
- A plan's `selectedTests` and `skippedTests` do not match Swift Testing tests. The identifiers reach
  the runner as `OnlyTestIdentifiers`, so a plan that selects any runs zero tests, and a plan that
  skips one skips nothing. Suite, method, and target-qualified spellings all behave the same.
  Command-line `-only-testing` works and replaces the plan's selection. Selecting a whole target in
  a plan works.

Retires when a later Xcode matches plan selection against Swift Testing names.

## A plan's skippedTags skips nothing

Observed 2026-10-13 on Xcode 27.0 (build 27A266a). A `Quick` plan that skipped the `slow` and
`gpu` tags on every target still ran the `.gpu` suites, such as `RendererUpscaleTests`. Both
`"gpu"` and the spelling Xcode itself writes, `".gpu"`, behave the same. A plan's `selectedTags`
works: the `GPU` plan runs only `.gpu` tests. So `Quick` skips through the environment variable
`OPENSKY_SKIPPED_TAGS` and a condition trait instead ([test runs](/tools/test-runs.md#tags)).

Retires when a plan with `skippedTags` and no `OPENSKY_SKIPPED_TAGS` lists no `.gpu` suite in its
transcript.

## The Neural Engine compiler can stop answering

Observed 2026-10-13 on macOS 27.0.1. `ANECompilerService`, the system service that compiles
models for the Neural Engine, ran at 99% CPU and answered nothing for at least two hours: runs
at 10:46 and 12:32 UTC both hung on it. It recovered on its own by 12:45, with no restart.
MetalFX builds its temporal scaler through it, and the renderer then built the scaler on the main
actor. So `RendererUpscaleTests` blocked the main actor, and every other main-actor test of the
run waited behind it until one of them hit its 2-minute allowance. The spindump that
`xcodebuild` attaches to that failure in the result bundle shows the stack:
`newTemporalScalerWithDevice` waits on `aned`.

The renderer now builds the scalers off the main actor and draws at full size until they arrive
([upscaling](/rendering/upscaling.md#building-the-scaler)), so a stuck service no longer
freezes the game. `MetalFXCompilerProbe` asks the service before the MetalFX tests run, so they
fail with a clear message instead of waiting out their allowance.

Retires when MetalFX builds its scalers without the Neural Engine.

## Package framework variants warn about declared dependencies

Observed 2026-10-01 on Xcode 26 and on Xcode 27.0 (27A266a). A unit build printed hundreds of
lines like `warning: 'OpenSkyFormatsESM' is missing a dependency on 'OpenSkyFormatsCore' because
dependency scan of Swift module 'OpenSkyFormatsESM' discovered a dependency on
'OpenSkyFormatsCore'`, although `Package.swift` declares the dependency. Every package target that
compiled named its whole dependency closure. The app links each engine target through
`OpenSkyModules`. A test bundle links the same targets again through the testing and fixture
libraries. So Xcode builds each of them as its dynamic variant, a framework in
`Products/Debug/PackageFrameworks/`. The CLI build links them statically and never warned.

The check is Swift Build's `DIAGNOSE_MISSING_TARGET_DEPENDENCIES`. With `EnableDebugActivityLogs=YES`
in the environment, the warning names target GUIDs: the dependent is
`PACKAGE-TARGET:OpenSkyFormatsESM-<hash>-dynamic`, and the dependency is the static
`PACKAGE-TARGET:OpenSkyFormatsCore`. The check walks the target graph from before the switch to
dynamic variants, so it finds no edge from a variant. Upstream fixed this in
[swift-build PR 1457](https://github.com/swiftlang/swift-build/pull/1457), "Fix dependency
diagnostics for dynamic target variants".

`config/Build/Overrides.xcconfig` turns the check off where `MACH_O_TYPE` is `mh_dylib`. In this
workspace only the package variants are dylibs. Their imports are still checked against
`Package.swift` by `make module-graph` (rule 7).

Retires when the installed Xcode ships that fix: delete the override, and a clean
`make build-tests` prints no `is missing a dependency on` line.

## A compilation cache hit leaves the driver record dirty

Observed 2026-10-01 on Xcode 27.0 (27A266a). In swift-build, `SwiftDriverJobTaskAction` returns
`.succeeded` for a compile job that the compilation cache replays. It does not call
`jobFinished`, so the Swift driver never learns that the job ran. The driver then writes each of
those files into its build record (`<Module>-primary.priors`) as `needsNonCascadingBuild`. The
next time the driver plans that module, it compiles every file again, again from the cache, so
the record never becomes clean. Source: `Sources/SWBTaskExecution/TaskActions/SwiftDriverJobTaskAction.swift`
in [swift-build](https://github.com/swiftlang/swift-build), still so at commit `748527d` (2026-09-30).

The driver plans a module again only when its planning task's signature changes. Two builds in
the same context skip it. A plain `build` and a `build-for-testing`, or the `OpenSky` and
`OpenSkyCLI` schemes, give it different signatures: a switch between the schemes recompiled
`OpenSkyFormatsCore` and `OpenSkyDiagnostics` (records left dirty by earlier cache hits) and
relinked and re-signed every framework above them. That is why `make build-tests` builds the
CLI through the `OpenSky` scheme.

A test plan is not part of the signature, but the variant is. Xcode builds a package target that
the app and an app-hosted test bundle both link as a dynamic variant, a separate target with its
own signature that writes the same intermediates, and only in a build that holds such a bundle.
So on 2026-10-05 every change between the `Quick` and the `UnitTests` plan replanned the 36
modules the app links, replayed every file their shared record marked (201 in a worked
checkout, all 1,553 after a fresh replay), and relinked the 30 bundles: 16 to 35 s. The scheme
now builds `OpenSkyTests` for testing in every plan, so every build holds the bundle and the
variants never change: two warm runs of different plans compile and link nothing. Giving each
variant its own `TARGET_TEMP_DIR` was tried first and left the static record dirty.

To see the driver's reasons, export `ADDITIONAL_SWIFT_DRIVER_FLAGS=-driver-show-incremental`
before a build. The same flag in `OTHER_SWIFT_FLAGS` does nothing. A record dirtied this way shows
`Scheduling noncascading build` for every file.

Retires when swift-build reports a replayed job to the driver: then `make build-cli` followed by
`make test-unit` compiles no Swift file, and the scheme no longer needs to build `OpenSkyTests`
in every plan.

## A new protocol requirement can shift stale witness slots

Observed 2026-10-09 on Xcode 27.0. A requirement added in the middle of `PapyrusWorldBridge`
moved every later witness slot. The incremental build did not recompile the unchanged files
that call the protocol, so `globalValue(for:)` ran the `write(_:for:)` witness and crashed
with `EXC_BAD_ACCESS`. Add a requirement at the end of a protocol, or touch its callers
before a local build. A clean CI build is not affected.

The same happens to a struct's layout. Observed 2026-10-11: a stored property added to
`CellStreamerNPCMovementState` recompiled its own file but not `CellStreamer.swift`, which stores
the struct in the class. The app read the new field past the old layout and crashed with
`EXC_BAD_ACCESS` at a small address. Touch the files that store a struct whose stored properties
changed before a local build.

## A failed compile skips the files that depend on it

Observed 2026-10-17 on Xcode 27.1 (27A9275), Swift 6.4. A build moved stored properties of
`PapyrusWorldStateBridge` into nested structs and failed in another file of the same module.
The driver compiled the changed files, logged `not scheduling dependents of
PapyrusWorldStateBridge.swift; unknown changes`, and stopped. The next build, with the error
fixed, compiled only the fixed file. The bridge's extension files kept their old field
offsets, and the hosted tests crashed with `EXC_BAD_ACCESS`. A layout change in a build
that does not fail recompiled every dependent file, in its own module and in the modules above.
Reproduced by adding a stored property and a type error in one build, then removing the
error. `tools/failed-build-records.sh` works around it
([build system](/tools/build-system.md#driver-records-after-a-failed-build)).

Retires when the driver keeps the skipped dependents in its record after a failed job: then the
reproduction passes with the script's call removed from `tools/xcodebuild-run.sh`.

## xcodebuild aborts when the test step re-resolves the package graph

Observed 2026-10-26 on Xcode 27.1 (27A9275), three runs in a row in the main checkout.
`make test-unit` built the Quick plan (`** TEST BUILD SUCCEEDED **`). The test step then
printed `Resolve Package Graph` 16 to 20 times and aborted with `** INTERNAL ERROR:
DVTInvalidation.swift:37 ... Message sent to invalidated object:
<IDESwiftPackageTestBundleProductBuildable ...>`. Every run in a linked worktree from
2026-10-17 to 2026-10-23 printed it once or twice and passed.

The likely cause: the main checkout is the package root, and it holds `.cache/Build/`, where
every build writes, and `.claude/worktrees/`, where other sessions edit and build their own
`Package.swift` trees. Xcode re-resolves when it sees files change under the root. In a
linked worktree neither folder is under the root. So build and test from a linked worktree.
`make test-rerun` runs a built plan through its `.xctestrun`, without the package graph,
and passed in the main checkout.

Retires when `make test-unit` in the main checkout runs its tests while another worktree
builds.

## A stopped signing step leaves a `.cstemp` file

Observed 2026-10-04. When a build stops while `codesign` runs, it can leave a `<binary>.cstemp`
file inside the bundle. The next build of that variant fails with
`invalid or unsupported format for signature` and `In subcomponent: ... .cstemp`. Seen in the
sanitizer variants under `Build/Products/Variant-*` in the build cache. Delete the leftovers with
`find "$OPENSKY_DERIVED_DATA/Build/Products" -name '*.cstemp' -delete` and build again.

Retires when Xcode cleans its own signing temp files.

## No Skyrim saves on this machine

Observed 2026-10-06. The game was never launched on this machine, so no `.ess` save exists.
The [ESS](/formats/ess.md) layouts are checked only against synthetic saves, and
`ESSRealDataTests` skips. To run it, set `OPENSKY_SKYRIM_SAVES` to a folder of saves and run
`make test-real`.

Retires when a real save has been read and the "Confirmed on real data" section of the ESS
pages is filled in.

## Periphery comes from the Homebrew core formula

Observed 2026-10-08. The cask in the `peripheryapp/periphery` tap no longer installs:
Homebrew stopped `depends_on macos: :catalina`. The weekly workflow installs the core
formula (`brew install periphery`) instead. Homebrew marks that formula deprecated, because
the upstream repository is archived, and plans to disable it on 2027-08-12.

Retires when Periphery has a maintained install path again, or when `make health` moves to
another tool.

## Local Xcode 27.2 is newer than the CI pin

Observed 2026-10-30. This machine updated to Xcode 27.2 (27B52), with Apple Swift 6.4.2.
CI pins Xcode 27.0 and Swift 6.4, so `make check` fails at `swift-baseline`. The update also
removed the Metal Toolchain: the shader step failed until `xcodebuild -downloadComponent
MetalToolchain` ran again. Nobody has checked yet whether the `xcode-27` runner has Xcode 27.2.
Until the pins match, run the other `check` steps on their own:
`make format-check lint docs-links`.

Retires when local Xcode and the CI pin name the same Swift version.
