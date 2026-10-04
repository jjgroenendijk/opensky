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

## Upstream spec hosts

Quirks that cost time in every format parser session. Each retires when the host changes behavior.

- Observed 2026-07-20: UESP (`en.uesp.net`, `ck.uesp.net`) answers the WebFetch tool with HTTP 403.
  Use `curl -sL -A 'Mozilla/5.0' '<url>'`.
- Observed 2026-07-20: the `TES5Edit/TES5Edit` default branch is `dev-4.1.6`, not `main` or `dev`.
  Raw file URLs return 404 on the wrong branch. Check with `gh api repos/TES5Edit/TES5Edit`.
- Observed 2026-09-08: `ck.uesp.net` answers a direct `curl` with a Cloudflare "Just a moment..."
  page, so the user agent trick no longer works there. Its Wayback snapshots still load
  (`https://web.archive.org/web/2023/https://ck.uesp.net/wiki/<Page>`). Pages the Wayback Machine
  never saved cannot be reached from here. For a Papyrus signature, the install's own compiled
  script is the better source anyway ([actor natives](/engine/papyrus-actor-natives.md)).
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
treats as a program on a removable volume, because `DerivedData/` is on an external disk. The grant
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

## xctrace --launch never starts the process

Observed 2026-10-01 on xctrace 27.0. `xcrun xctrace record --template 'Time Profiler' --launch --
openskycli ...` printed "Launching process" and then waited for more than ten minutes. The CLI sat
at 0% CPU with about 90 KB resident, so it never ran its first line. Starting the CLI first and
attaching with `--attach <pid>` recorded normally, and `tools/profile.sh` does that
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

## A cached module emit can leave a stale module in Products

Observed 2026-09-29 and 2026-09-30 on Xcode 26, for at least eight package modules. After a change
to the public interface of a package module, the build wrote the new module under
`DerivedData/Build/Intermediates.noindex/`. The copy in
`DerivedData/Build/Products/Debug/<Module>.swiftmodule` kept the old interface, or had no
`.swiftmodule` file at all. The next module up failed with "extra argument", "has no member", or
"cannot find type in scope", on repeated builds and with a forced rebuild. It happened with the "Emitting
module" step both a compilation cache hit and a miss. Deleting the Products copy fixed the next
build. `tools/xcodebuild-run.sh` does that delete itself
([build system](/tools/build-system.md#stale-module-copies)).

Once, after the delete, the next `make test-unit` ran test bundles built against the old struct layout
and crashed with `EXC_BAD_ACCESS` in "outlined init with copy". A forced rebuild fixed that.

Retires when an interface change builds through xcodebuild without the delete.

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

`Config/Build/Overrides.xcconfig` turns the check off where `MACH_O_TYPE` is `mh_dylib`. In this
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
`OpenSkyCLI` schemes, give it different signatures. So a switch between them recompiled
`OpenSkyFormatsCore` and `OpenSkyDiagnostics` (records left dirty by earlier cache hits) and
relinked and re-signed every framework above them. That is why `make build-tests` builds the
CLI through the `OpenSky` scheme.

To see the driver's reasons, export `ADDITIONAL_SWIFT_DRIVER_FLAGS=-driver-show-incremental`
before a build. The same flag in `OTHER_SWIFT_FLAGS` does nothing. A record dirtied this way shows
`Scheduling noncascading build` for every file.

Retires when swift-build reports a replayed job to the driver: then `make build-cli` followed by
`make test-unit` compiles no Swift file.

## A stopped signing step leaves a `.cstemp` file

Observed 2026-10-04. When a build stops while `codesign` runs, it can leave a `<binary>.cstemp`
file inside the bundle. The next build of that variant fails with
`invalid or unsupported format for signature` and `In subcomponent: ... .cstemp`. Seen in the
sanitizer variants under `DerivedData/Build/Products/Variant-*`. Delete the leftovers with
`find DerivedData/Build/Products -name '*.cstemp' -delete` and build again.

Retires when Xcode cleans its own signing temp files.
