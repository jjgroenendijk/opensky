# AGENTS.md — OpenSkyRealDataTests

Every env-gated suite that runs against the user's own Skyrim SE install, and nothing else.
The `RealData` plans select this target. General test rules live in `src/Tests/AGENTS.md`;
only what differs is below. Checking a hypothesis against the install is a different job:
load the `probing-real-game-data` skill for that.

## What belongs here

A suite whose test bodies read the real install. Copy the shape of
`CellRenderRealDataTests.swift`: gate every test on `RealDataEnvironment`
(`.enabled(if: RealDataEnvironment.hasDataRoot)`, or `canRender` when it also needs a Metal 4
device), then `try #require(RealDataEnvironment.dataRoot)`. Do not declare a `dataRoot` or
`device` of your own. Inside a test host, `GameDataLocator` withholds every other data root,
so a suite that forgets its gate cannot reach an install.

Shared loading goes in a fixture, not in each suite: `RealDataInstall` loads `Skyrim.esm`
with its texture and mesh libraries, `PlayerBodyFixture.stage()` stands the player in a cell,
and `HeimskrFace` frames an actor's head. Keep one gated suite per file, named after the file.
A gated suite outside this folder would never run (gate: `tools/lint/realdata-plan.sh`).

Support code only these suites use stays here. Support shared with the synthetic suites goes
in `src/Tests/HostedTestSupport/`.

## Running them

```sh
make test PLAN=RealData T='CellRenderRealDataTests/streamsFiveByFiveGridToCompletion()'
make test PLAN=RealDataAll
make test PLAN=Perf
```

`make test` runs the real-data plans under a memory watchdog (`CAP=` in MB). A heavy real-data test
once reached about 30 GB resident and locked the machine, so never run one through a raw
`xcodebuild`.

## Legal boundary

No game-derived bytes leave a run: assert on counts, editor IDs, and shapes, and write any
artifact, a render capture included, to `.logs/` through a run directory. Find `.logs/` with
`RepositoryLogs.directory()`, never `#filePath`. Compare offscreen frames with
`RenderedPixels`.
