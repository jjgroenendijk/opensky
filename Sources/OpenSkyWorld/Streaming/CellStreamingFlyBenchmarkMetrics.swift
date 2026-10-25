// Fly-bench metric validation, split from CellStreamingFlyBenchmark.swift
// (file-length limit). Collision + actor per-cell metrics are validated
// against their budgets and the 5.5 exact-accounting / 5.6 zero-unexplained
// rules; Driver hands in its runner + configuration.

import Foundation
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyRendering

nonisolated public struct ActorBuildBenchmarkSummary: Sendable {
    public let p95: Double
    public let discovered: Int
    public let rendered: Int
    public let failures: Int
    public let animated: Int
    /// Cells with build metrics, one per touched cell.
    public let cellCount: Int
}

nonisolated public func validatedFlyUpdateBudgets(
    render: OffscreenBenchResult,
    configuration: CellStreamingFlyBenchmarkConfiguration
) throws {
    guard
        render.animationAverageMS <= configuration.animationUpdateBudgetMS,
        render.animationPercentileMS(95) <= configuration.animationUpdateBudgetMS
    else {
        throw CellStreamingFlyBenchmarkError.animationUpdateExceeded(
            average: render.animationAverageMS,
            p95: render.animationPercentileMS(95),
            budget: configuration.animationUpdateBudgetMS
        )
    }
    guard
        render.shadowAverageMS <= configuration.shadowUpdateBudgetMS,
        render.shadowPercentileMS(95) <= configuration.shadowUpdateBudgetMS
    else {
        throw CellStreamingFlyBenchmarkError.shadowUpdateExceeded(
            average: render.shadowAverageMS,
            p95: render.shadowPercentileMS(95),
            budget: configuration.shadowUpdateBudgetMS
        )
    }
    guard
        render.audioUpdateAverageMS <= configuration.audioUpdateBudgetMS,
        render.audioUpdatePercentileMS(95) <= configuration.audioUpdateBudgetMS
    else {
        throw CellStreamingFlyBenchmarkError.audioUpdateExceeded(
            average: render.audioUpdateAverageMS,
            p95: render.audioUpdatePercentileMS(95),
            budget: configuration.audioUpdateBudgetMS
        )
    }
    guard
        render.scriptUpdateAverageMS <= configuration.scriptUpdateBudgetMS,
        render.scriptUpdatePercentileMS(95) <= configuration.scriptUpdateBudgetMS
    else {
        throw CellStreamingFlyBenchmarkError.scriptUpdateExceeded(
            average: render.scriptUpdateAverageMS,
            p95: render.scriptUpdatePercentileMS(95),
            budget: configuration.scriptUpdateBudgetMS
        )
    }
}

nonisolated public func validateCollisionBuildMetrics(
    runner: SerialCellBuildRunner,
    configuration: CellStreamingFlyBenchmarkConfiguration,
    expectedCount: Int
) throws {
    let metrics = runner.buildMetricsSnapshot().values
    guard metrics.count == expectedCount else {
        throw CellStreamingFlyBenchmarkError.unexpectedBuildSet(
            expected: expectedCount,
            actual: metrics.count
        )
    }
    let durations = metrics.map(\.collisionDurationMS).sorted()
    guard !durations.isEmpty else { return }
    let p95 = durations[p95Index(count: durations.count)]
    let maximum = durations.last ?? 0
    guard p95 <= configuration.collisionBuildBudgetMS else {
        throw CellStreamingFlyBenchmarkError.collisionBuildExceeded(
            p95: p95,
            maximum: maximum,
            budget: configuration.collisionBuildBudgetMS
        )
    }
}

/// Exact per-cell accounting first (every discovered ACHR explained, every
/// failure reason-tagged — 5.6 zero-unexplained rule), then the latency
/// budget over the same per-cell durations. Count of metric entries is
/// validated by validateCollisionBuildMetrics.
nonisolated public func validatedActorBuildMetrics(
    runner: SerialCellBuildRunner,
    configuration: CellStreamingFlyBenchmarkConfiguration
) throws -> ActorBuildBenchmarkSummary {
    let metrics = runner.buildMetricsSnapshot()
    try validateActorAccounting(metrics)
    let durations = metrics.values.map(\.actorDurationMS).sorted()
    guard !durations.isEmpty else {
        return ActorBuildBenchmarkSummary(
            p95: 0, discovered: 0, rendered: 0, failures: 0, animated: 0, cellCount: 0
        )
    }
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
        p95: p95,
        discovered: metrics.values.reduce(0) { $0 + $1.actorDiscoveredCount },
        rendered: metrics.values.reduce(0) { $0 + $1.actorRenderedCount },
        failures: metrics.values.reduce(0) { $0 + $1.actorFailureCount },
        animated: metrics.values.reduce(0) { $0 + $1.actorAnimatedCount },
        cellCount: metrics.count
    )
}

nonisolated private func validateActorAccounting(
    _ metrics: [CellCoordinate: CellBuildMetric]
) throws {
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
    for (coordinate, metric) in metrics where !metric.actorAnimationAccountingIsExact {
        throw CellStreamingFlyBenchmarkError.actorAnimationAccountingMismatch(
            coordinate: coordinate,
            rendered: metric.actorRenderedCount,
            explained: metric.actorAnimatedCount + metric.actorAnimationFailureCount
        )
    }
    for (coordinate, metric) in metrics where !metric.actorAnimationFailuresAreExplained {
        throw CellStreamingFlyBenchmarkError.actorAnimationFailureUnexplained(
            coordinate: coordinate,
            failures: metric.actorAnimationFailureCount,
            reasons: metric.actorAnimationFailureReasons.count
        )
    }
}

nonisolated public func p95Index(count: Int) -> Int {
    min(count - 1, Int(ceil(Double(count) * 0.95)) - 1)
}
