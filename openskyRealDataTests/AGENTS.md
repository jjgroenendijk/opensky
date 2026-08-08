# AGENTS.md — openskyRealDataTests

Every env-gated suite that runs against the user's own Skyrim SE install, and nothing else.
This is the whole `RealData` test plan: the plan selects this target and does not narrow it
further, so a file here runs under `make realtest-all` by virtue of being here (issue #418).
General test rules live in `openskyTests/AGENTS.md`; only what differs is below. Running
engine code against the install to check a hypothesis is a different job — load the
`probing-real-game-data` skill for that.

## What belongs here

A suite whose test bodies read the real install. `CellRenderRealDataTests.swift` is the
canonical shape — copy it. Gate on `GameDataLocator.environmentKey` being set through a
`static let dataRoot: GameDataRoot?`, and deliberately do not consult the Steam-default
fallback, so a machine without `OPENSKY_DATA_ROOT` skips deterministically. The env var is
the only way in: `GameDataLocator` withholds the persisted `OpenSkyDataRoot` default and the
Steam fallback inside a test host, so a suite that forgets its gate cannot quietly reach an
install (issue #362).

Keep one gated suite per file, named after the file. `make realdata-plan` (part of
`make lint`) fails when a file declaring `dataRoot: GameDataRoot?` with a `@Test` sits under
`openskyTests/` or `openskyTestSupport/` instead of here, because such a suite would never
run: `make realtest-all` would not reach it, and inside `make test` it would silently skip,
since a plain `xcodebuild test` does not forward `OPENSKY_DATA_ROOT` into the host.

Support code only these suites use — a probe harness, a report writer, a real-terrain
driver — belongs here too. Support shared with the synthetic suites goes in
`openskyTestSupport/`, which both test targets compile.

## Running them

```sh
make realtest T='CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'
make realtest-all
make realtest-perf
```

A bare selector resolves under `openskyRealDataTests/`. All three run under the RSS
watchdog, which is mandatory: a heavy real-data test once reached ~30 GB resident and locked
the machine. Never run one through a raw `xcodebuild` that bypasses it. `make test` never
runs anything here, and this bundle is not compiled at all under the `UnitTests` plan.

## Legal boundary

No game-derived bytes leave a run: assert on counts, editor IDs and shapes, and write any
artifact — a render capture included — to gitignored `logs/` through a run directory. A
rendered frame embeds the user's assets, so it is game content (root `AGENTS.md`).
