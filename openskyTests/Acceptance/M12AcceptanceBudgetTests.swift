// M12 acceptance, budget half (issue #180): a cell carrying a populated
// inventory and an equipped actor, and a frame run with menus open, are held to
// the same budgets everything else is.
//
// Deliberately no new gate. Both cases run the shipping validators —
// `validatedActorBuildMetrics` and `validatedFlyUpdateBudgets` — over the
// shipping `CellStreamingFlyBenchmarkConfiguration`, so the numbers the CLI
// bench enforces are the numbers asserted here. A second mechanism would be a
// second set of numbers to keep in step, which is exactly what the issue's
// "extend them" means to avoid.
//
// What is synthetic is the timing, as it is throughout
// `CellStreamingFlyPathTests`: these cases pin the gate's behaviour, not this
// machine's speed. Measured timings against the real install come from
// `openskycli bench --fly-path`, which cannot run in a unit test.

import Foundation
@testable import opensky
import Testing

/// A provider whose builds report whatever summary the case needs, so the real
/// `SerialCellBuildRunner` produces real `CellBuildMetric` values to validate.
nonisolated private final class BudgetCellProvider: CellSceneProvider {
    private let mutate: @Sendable (inout CellLoadSummary) -> Void

    init(mutate: @escaping @Sendable (inout CellLoadSummary) -> Void) {
        self.mutate = mutate
    }

    func buildCell(at coordinate: CellCoordinate, state _: WorldStateSnapshot) throws -> CellScene {
        var summary = CellLoadSummary(
            cellName: "m12-budget", gridX: coordinate.x, gridY: coordinate.y,
            totalRefCount: 0, drawnRefCount: 0,
            unsupportedBaseSkipCount: 0, markerSkipCount: 0,
            modelFailureSkipCount: 0, malformedRefSkipCount: 0,
            modelCount: 0, textureCount: 0, missingTextureCount: 0
        )
        mutate(&summary)
        return CellScene(
            renderScene: RenderScene(instances: []),
            summary: summary,
            bounds: nil,
            staticCollision: .empty
        )
    }

    func evict(droppingMeshKeys _: Set<String>, droppingTextureKeys _: Set<String>) {}
}

struct M12AcceptanceBudgetTests {
    /// The shipping fly-path budgets, matching `openskycli bench --fly-path`'s
    /// own defaults. Written out rather than imported because they are private
    /// to the command; a drift between the two is what the comment on the
    /// command's constants exists to prevent.
    private static func configuration(
        actorBuildBudgetMS: Double = 3000
    ) -> CellStreamingFlyBenchmarkConfiguration {
        CellStreamingFlyBenchmarkConfiguration(
            start: CellCoordinate(x: 0, y: 0),
            size: (width: 1, height: 1),
            maxFrames: 1,
            footprintCapMB: 1024,
            collisionBuildBudgetMS: 750,
            actorBuildBudgetMS: actorBuildBudgetMS,
            animationUpdateBudgetMS: 4,
            shadowUpdateBudgetMS: 1.5,
            audioUpdateBudgetMS: 0.5,
            scriptUpdateBudgetMS: 0.5
        )
    }

    /// A cell whose actor is dressed from a runtime equipped set, carrying the
    /// appearance skips issue #180 added. Rendered, not failed: a masked skin
    /// part is a resolution decision.
    private static func equippedSummary(durationMS: Double) -> @Sendable (
        inout CellLoadSummary
    ) -> Void {
        { summary in
            summary.actorCount = 1
            summary.actorDrawnCount = 1
            summary.actorAnimatedCount = 1
            summary.actorBuildDurationMS = durationMS
            summary.actorAppearanceSkipReasons = [
                "ACHR 00000900: maskedByOutfit (00000310)",
                "ACHR 00000900: unrenderableEquipment (00000500)"
            ]
        }
    }

    private static func runBuild(
        _ mutate: @escaping @Sendable (inout CellLoadSummary) -> Void
    ) throws -> SerialCellBuildRunner {
        let runner = SerialCellBuildRunner(provider: BudgetCellProvider(mutate: mutate))
        runner.enqueue(CellCoordinate(x: 6, y: -2), state: .empty)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, runner.drainCompleted().isEmpty {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return runner
    }

    // MARK: - Cell build time

    /// The gate passes for an equipped actor inside budget, and the new
    /// appearance-skip list does not disturb the exact-accounting rule that
    /// the same validator enforces alongside the timing.
    @Test
    func anEquippedActorsCellBuildStaysWithinTheShippingBudget() throws {
        let runner = try Self.runBuild(Self.equippedSummary(durationMS: 12))
        let summary = try validatedActorBuildMetrics(
            runner: runner, configuration: Self.configuration()
        )
        #expect(summary.discovered == 1)
        #expect(summary.rendered == 1)
        #expect(summary.failures == 0)
        #expect(summary.p95 == 12)

        let metric = try #require(
            runner.buildMetricsSnapshot()[CellCoordinate(x: 6, y: -2)]
        )
        #expect(metric.actorAccountingIsExact)
        #expect(metric.actorFailuresAreExplained)
    }

    /// The gate has not been weakened by the M12 additions: the same build over
    /// budget still produces the reason-tagged error, with the measured value
    /// and the budget both named.
    @Test
    func anOverBudgetEquippedCellBuildStillFailsTheGate() throws {
        let runner = try Self.runBuild(Self.equippedSummary(durationMS: 4000))
        #expect(throws: CellStreamingFlyBenchmarkError.self) {
            try validatedActorBuildMetrics(
                runner: runner, configuration: Self.configuration()
            )
        }
        do {
            _ = try validatedActorBuildMetrics(
                runner: runner, configuration: Self.configuration()
            )
        } catch let error as CellStreamingFlyBenchmarkError {
            #expect(error.errorDescription?.contains("4000.00 ms") == true)
            #expect(error.errorDescription?.contains("3000.00 ms budget") == true)
        }
    }

    // MARK: - Frame time

    /// A frame run with a menu open costs no more per-frame update work than
    /// one without: menu mode advances every sim clock by zero, so the
    /// animation, audio and script update budgets the same validator enforces
    /// are met by construction rather than by luck.
    @Test
    func framesRunWithAMenuOpenStayWithinTheUpdateBudgets() throws {
        let paused = OffscreenBenchResult(
            frameMS: [8, 9, 8],
            windowSummaries: [],
            animationMS: [0, 0, 0],
            shadowMS: [0.4, 0.5, 0.4],
            audioUpdateMS: [0, 0, 0],
            scriptUpdateMS: [0, 0, 0]
        )
        try validatedFlyUpdateBudgets(render: paused, configuration: Self.configuration())
        #expect(paused.animationAverageMS == 0)
        #expect(paused.scriptUpdatePercentileMS(95) == 0)

        // And the gate is live rather than vacuous: the same run with the
        // script VM working through a full inventory's worth of events past
        // its budget is refused.
        let busy = OffscreenBenchResult(
            frameMS: [8, 9, 8],
            windowSummaries: [],
            animationMS: [0, 0, 0],
            shadowMS: [0.4, 0.5, 0.4],
            audioUpdateMS: [0, 0, 0],
            scriptUpdateMS: [1, 2, 3]
        )
        #expect(throws: CellStreamingFlyBenchmarkError.self) {
            try validatedFlyUpdateBudgets(render: busy, configuration: Self.configuration())
        }
    }
}
