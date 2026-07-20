// Fly-bench metric validation, split from CellStreamingFlyBenchmark.swift
// (file-length limit). Collision + actor per-cell metrics are validated
// against their budgets and the 5.5 exact-accounting / 5.6 zero-unexplained
// rules; Driver hands in its runner + configuration.

import Foundation

nonisolated struct CollisionBuildBenchmarkSummary {
    let average: Double
    let p95: Double
    let maximum: Double
    let shapes: Int
    let triangles: Int
}

nonisolated struct ActorBuildBenchmarkSummary {
    let average: Double
    let p95: Double
    let maximum: Double
    let discovered: Int
    let rendered: Int
    let disabledSkips: Int
    let failures: Int
    let cellReports: [ActorCellReport]
}

nonisolated func validatedCollisionBuildMetrics(
    runner: SerialCellBuildRunner,
    configuration: CellStreamingFlyBenchmarkConfiguration,
    expectedCount: Int
) throws -> CollisionBuildBenchmarkSummary {
    let metrics = runner.buildMetricsSnapshot().values
    guard metrics.count == expectedCount else {
        throw CellStreamingFlyBenchmarkError.unexpectedBuildSet(
            expected: expectedCount,
            actual: metrics.count
        )
    }
    let durations = metrics.map(\.collisionDurationMS).sorted()
    guard !durations.isEmpty else {
        return CollisionBuildBenchmarkSummary(
            average: 0,
            p95: 0,
            maximum: 0,
            shapes: 0,
            triangles: 0
        )
    }
    let average = durations.reduce(0, +) / Double(durations.count)
    let p95 = durations[p95Index(count: durations.count)]
    let maximum = durations.last ?? 0
    guard p95 <= configuration.collisionBuildBudgetMS else {
        throw CellStreamingFlyBenchmarkError.collisionBuildExceeded(
            p95: p95,
            maximum: maximum,
            budget: configuration.collisionBuildBudgetMS
        )
    }
    return CollisionBuildBenchmarkSummary(
        average: average,
        p95: p95,
        maximum: maximum,
        shapes: metrics.reduce(0) { $0 + $1.collisionShapeCount },
        triangles: metrics.reduce(0) { $0 + $1.collisionTriangleCount }
    )
}

/// Exact per-cell accounting first (every discovered ACHR explained, every
/// failure reason-tagged — 5.6 zero-unexplained rule), then the latency
/// budget over the same per-cell durations. Count of metric entries is
/// validated by validatedCollisionBuildMetrics.
nonisolated func validatedActorBuildMetrics(
    runner: SerialCellBuildRunner,
    configuration: CellStreamingFlyBenchmarkConfiguration
) throws -> ActorBuildBenchmarkSummary {
    let metrics = runner.buildMetricsSnapshot()
    for (coordinate, metric) in metrics where !metric.actorAccountingIsExact {
        throw CellStreamingFlyBenchmarkError.actorAccountingMismatch(
            coordinate: coordinate,
            discovered: metric.actorDiscoveredCount,
            explained: metric.actorRenderedCount
                + metric.actorDisabledSkipCount
                + metric.actorFailureCount
        )
    }
    for (coordinate, metric) in metrics where !metric.actorFailuresAreExplained {
        throw CellStreamingFlyBenchmarkError.actorFailureUnexplained(
            coordinate: coordinate,
            failures: metric.actorFailureCount,
            reasons: metric.actorFailureReasons.count
        )
    }
    let cellReports = metrics
        .sorted { ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y) }
        .map { coordinate, metric in
            ActorCellReport(
                coordinate: coordinate,
                discovered: metric.actorDiscoveredCount,
                rendered: metric.actorRenderedCount,
                disabledSkips: metric.actorDisabledSkipCount,
                failures: metric.actorFailureCount,
                failureReasons: metric.actorFailureReasons
            )
        }
    let durations = metrics.values.map(\.actorDurationMS).sorted()
    guard !durations.isEmpty else {
        return ActorBuildBenchmarkSummary(
            average: 0, p95: 0, maximum: 0,
            discovered: 0, rendered: 0, disabledSkips: 0, failures: 0,
            cellReports: []
        )
    }
    let average = durations.reduce(0, +) / Double(durations.count)
    let p95 = durations[p95Index(count: durations.count)]
    let maximum = durations.last ?? 0
    guard p95 <= configuration.actorBuildBudgetMS else {
        throw CellStreamingFlyBenchmarkError.actorBuildExceeded(
            p95: p95,
            maximum: maximum,
            budget: configuration.actorBuildBudgetMS
        )
    }
    return ActorBuildBenchmarkSummary(
        average: average,
        p95: p95,
        maximum: maximum,
        discovered: metrics.values.reduce(0) { $0 + $1.actorDiscoveredCount },
        rendered: metrics.values.reduce(0) { $0 + $1.actorRenderedCount },
        disabledSkips: metrics.values.reduce(0) { $0 + $1.actorDisabledSkipCount },
        failures: metrics.values.reduce(0) { $0 + $1.actorFailureCount },
        cellReports: cellReports
    )
}

nonisolated func p95Index(count: Int) -> Int {
    min(count - 1, Int(ceil(Double(count) * 0.95)) - 1)
}
