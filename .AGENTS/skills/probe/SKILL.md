---
name: probe
description: Run engine code against the real Skyrim SE install to check a
  parser/renderer hypothesis - scratch test template, env gating, MainActor rules,
  offscreen render verification. Use before writing ad-hoc swift scripts or
  throwaway test classes.
---

# Probing real game data

Sanctioned path for "run engine code against the real install and look at the
result". Replaces ad-hoc `swift` scripts (fail on top-level statements + unhandled
`try`) and hand-rolled throwaway test classes. Probes are throwaway: never land in
commits (AGENTS.md reverse-engineering rule).

## Template — scratch test class

Copy the shape of `openskyTests/CellRenderRealDataTests.swift` (the canonical
env-gated real-data test). Minimal scratch probe:

```swift
import Foundation
@testable import opensky
import Testing

struct ScratchProbeTests {
    /// Env override only — Steam-default fallback deliberately not consulted,
    /// so machines without OPENSKY_DATA_ROOT skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let env = ProcessInfo.processInfo.environment
        guard let path = env[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func probe() throws {
        let root = try #require(Self.dataRoot)
        // ... hypothesis check here. `print()` shows in the LIVE xcodebuild
        // console but is NOT in the .xcresult, so `make test-report` and any
        // backgrounded/polled run lose it. To capture a result, write an
        // artifact to logs/ (PNG, sidecar .txt) or #expect on a value.
    }
}
```

Run: `OPENSKY_DATA_ROOT="/Volumes/data/steam/steamapps/common/Skyrim Special Edition" \
make test-one T=ScratchProbeTests`. Failures detail (names + messages from the
result bundle): `make test-report`.

For a real-data test that must actually execute against the install: plain
`xcodebuild test` does NOT forward `OPENSKY_DATA_ROOT` to the unit-test host, so
env-gated tests silently skip. Use `make realtest T='Class/method()'` — it
injects the data root the reliable way and runs under the RSS watchdog
(`tools/realtest.sh`). The selector must resolve to exactly one fully-qualified
test.

## Rules that prevent the usual compile failures

- Test fn touching Renderer / MTKView / any AppKit or MetalKit API -> mark it
  `@MainActor` (pattern: `RendererOffscreenTests`, `CellRenderRealDataTests`).
  Skipping this is the historical top compile error (`error: main actor`).
- Everything parsing external data throws -> `try` + `#require`, no force-unwrap
  (lint errors, AGENTS.md).
- Metal probe -> gate on `device.supportsFamily(.metal4)` like
  `CellRenderRealDataTests.device`, so CI + non-Metal4 machines skip.
- No `swift path/to/script.swift` one-liners against engine sources — the engine
  is not a package; scripts cannot import `opensky` and die on top-level
  statement rules. Always probe via the test target or `openskycli`.

## Rendering verification

Screen Recording TCC is missing on this machine; UI-test automation flaky. Reliable
paths, in order. Render captures are temporary or `logs/`-local; never add image files to
the repo:

1. `Renderer.renderOffscreen` from a unit test — deterministic pixel assertions first;
   optional local temp capture for human review (`RendererOffscreenTests`).
2. `make run-cli ARGS="render --out logs/frame.png ..."` (see `docs/tools/cli.md`).
3. Ask the user to look at the running app (they see launched apps).

If a real-data XCTest host hangs at 0% CPU before running (a known flake on this
machine — see `docs/testing.md`), do not keep killing and retrying it: move the
one-off check into `openskycli` and drive it with `make run-cli`. The CLI is the
first-choice real-data probe surface here, not a fallback. UI tests blocking on
"enabling automation mode" is the same TCC class — run `make test-perms` once.

## Prefer openskycli when it already covers the question

`vfs ls|cat`, `record`, `cell`, `nif`, `dds`, `render`, `bench` cover most lookups:
`make run-cli ARGS="record --type LAND ..."` beats writing a probe. Probe recurs
across sessions -> promote it to an `openskycli` subcommand (rules in
`openskycli/AGENTS.md`).

## Cleanup

Before commit: scratch test files deleted, `git status` clean of probe artifacts.
Probe findings worth keeping -> `docs/formats/<name>.md` or a code comment at the
parse site, not the probe itself.
