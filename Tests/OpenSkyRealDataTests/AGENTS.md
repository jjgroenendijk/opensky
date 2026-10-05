# AGENTS.md — OpenSkyRealDataTests

Every env-gated suite that runs against the user's own Skyrim SE install, and nothing else.
This is the whole `RealData` test plan: the plan selects this target and does not narrow it
further, so a file here runs under `make test-real` by virtue of being here (issue #418).
General test rules live in `Tests/OpenSkyTests/AGENTS.md`; only what differs is below. Running
engine code against the install to check a hypothesis is a different job — load the
`probing-real-game-data` skill for that.

## What belongs here

A suite whose test bodies read the real install. `CellRenderRealDataTests.swift` is the
canonical shape — copy it. Gate every test on `Support/RealDataEnvironment.swift`:
`.enabled(if: RealDataEnvironment.hasDataRoot)`, or `canRender` when it also needs a Metal 4
device, then `try #require(RealDataEnvironment.dataRoot)`. Do not declare a `dataRoot` or
`device` of your own. The gate reads only `OPENSKY_DATA_ROOT`, so a machine without it
skips. `GameDataLocator` also withholds the persisted `OpenSkyDataRoot` default and the
Steam fallback inside a test host, so a suite that forgets its gate cannot reach an install.

Shared loading goes in a fixture, not in each suite: `RealDataInstall` loads `Skyrim.esm`
with texture and mesh libraries, `PlayerBodyFixture.stage()` stands the player in a cell,
and `HeimskrFace` frames an actor's head.

Keep one gated suite per file, named after the file. `make realdata-plan` (part of
`make lint`) fails when a file that reads `RealDataEnvironment` or declares
`dataRoot: GameDataRoot?` has a `@Test` outside this folder, because such a suite would
never run: `make test-real` would not reach it, and a plain `xcodebuild test` does not
forward `OPENSKY_DATA_ROOT` into the host.

Support code only these suites use — a probe harness, a report writer, a real-terrain
driver — belongs here too. Support shared with the synthetic suites goes in
`Tests/TestSupport/`, which both test targets compile.

## Running them

```sh
make test-real T='CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'
make test-real
make test-real PERF=1
```

A bare selector resolves under `OpenSkyRealDataTests/`. All three run under the RSS
watchdog, which is mandatory: a heavy real-data test once reached ~30 GB resident and locked
the machine. Never run one through a raw `xcodebuild` that bypasses it. `make test-unit` never
runs anything here, and this bundle is not compiled at all under the `UnitTests` plan.

## Legal boundary

No game-derived bytes leave a run: assert on counts, editor IDs and shapes, and write any
artifact — a render capture included — to gitignored `.logs/` through a run directory. A
rendered frame embeds the user's assets, so it is game content (root `AGENTS.md`).

Find `.logs/` with `RepositoryLogs.directory()`, never `#filePath`: the compilation cache's
prefix mapping compiles source paths to `/^src/...`. Read back and compare offscreen frames
with `RenderedPixels` rather than another local copy.
