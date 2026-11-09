---
type: Decision
title: Deterministic game rules
description: Game rules read no hidden random source or clock, package modules hold no global
  mutable state or singletons, and no module uses the system notification centre. The allowed
  switches and sinks, the stopwatch, and how the check works.
tags: [decision, simulation, determinism, lint, code-quality]
---

# Deterministic game rules

The simulation runs on the main actor in a fixed order, so the same inputs give the same game state.
Three rules keep that true, and `tools/lint/deterministic-rules.sh` (in `make check` and CI) checks
them over every tracked Swift file of a package module.

| Rule | Where | What fails the check |
| --- | --- | --- |
| No hidden randomness or clock | Game-rule code: every module that `src/Package.swift` declares with `feature`, `domain`, or `interface`, its `Interface` module, and every pure core (`*Core.swift`) | A system random draw (`Float.random(in:)` without `using:`, `randomElement()`, `shuffled()`, `SystemRandomNumberGenerator`), `UUID()`, `Date()`, `Date.now`, and the system clocks (`DispatchTime.now`, `ContinuousClock`, `CACurrentMediaTime`, `systemUptime`, and the rest) |
| No global mutable state or singletons | Every package module | A stored `static var`, a file-scope `var`, `nonisolated(unsafe)` state, a `static let` that holds a lock, an atomic, a cache, or a queue, and a `static let shared` or `instance` |
| No hidden event bus | Every package module | `NotificationCenter`, `DistributedNotificationCenter`, and `Notification.Name` |

## What to write instead

- **Randomness.** A coordinator owns a seeded generator, as `LockCoordinator` does with
  `LockpickingRandom`. A closure seam whose default draws a number captures a `RandomStream` with
  a fixed seed: `{ [stream = RandomStream(seed: 0x4C4F_4F50)] range in stream.float(in: range) }`.
  Each seam has its own seed, so two seams never share a stream. A test sets the closure or the
  seed and checks the result.
- **Time.** The shell passes the time in: a frame delta, a `WallClock`, or a closure such as
  `PapyrusSessionNatives.realTimeSource`. A port that needs the calendar date asks for it, as
  `BenchmarkTourWorld.date` does.
- **Timing for logs and stats.** `Stopwatch` in `OpenSkyFormatsCore` is the one clock a game-rule
  module may read. It returns only a duration, which goes to a log line, a stats field, or a
  benchmark report, never into game state.
- **A unique temp file.** `FileManager.url(for: .itemReplacementDirectory, ...)` gives a fresh
  folder on the destination's volume, so no random name is needed.
- **A counter that must differ between values.** The value owns a counter object that its copies
  share, as `RenderInstancePoses` does with its `PoseRevision`.
- **Events.** A typed port or a `FrameSchedule` phase, so the module graph shows who listens.

`@TaskLocal` statics are allowed: their value is scoped to a task, not global.

## Allowed switches and sinks

The rule names these by type and member. Each is filled by one installer and read as a switch or
written as a sink. None of them holds game state.

| Global | Why it is process-wide |
| --- | --- |
| `EngineLogTap.lines` | The sink for error and fault log lines. Every logger writes it, and only the agent event stream reads it. |
| `LoadOptimisations.current` | Load-time optimisation switches. The app sets them once per world load, and `openskycli load-pass --set` sets them for a measured run. |
| `PlayerSettingsOverrides.values` | Settings one benchmark run forces. The benchmark host sets them once at launch, before the first store opens. |
| `RecordDecodeScope.openScopes` | The count of open decode scopes, so a FormID read outside any scope skips the task-local lookup. It belongs to the `@TaskLocal` scope beside it. |
| `AssetLoadQueue.shared`, `AssetLoadQueue.background` | One serial queue for play-time loads is the design, so loads never compete for the cores the cell build needs. A queue is an executor, not state. |

Adding a global to this table is a design change of the rule. It needs the reason in the table.

## The self-check

The script first runs each rule on small synthetic snippets. Each violation must fail, and each
clean snippet must pass, such as a seeded draw, a computed `static var`, a `@TaskLocal`, or an
allowed global. A rule that stops matching fails the check before it reads the tree.
