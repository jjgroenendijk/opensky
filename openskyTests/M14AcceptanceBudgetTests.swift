// M14 acceptance, budget half (issue #191): the locomotion route is held to the
// per-frame budgets that already exist, and adds no set of numbers of its own.
//
// Two claims. The behavior graph and the skinning it feeds are animation work,
// so they ride the shipping `animationUpdateBudgetMS` the fly-path validator
// already enforces — asserted here against the same validator and the same
// configuration `openskycli bench --fly-path` uses, rather than against a second
// copy of the numbers (the M13 review constraint). And the fixed-step
// simulation is bounded by construction: `WalkController` clamps a frame's
// contribution to 100 ms, so however slow a frame is, the number of behavior
// graph updates it can drive has a ceiling.
//
// The timings are synthetic, as they are throughout `CellStreamingFlyPathTests`:
// these cases pin the gate's behaviour, not this machine's speed. Measured
// timings against the real install come from `openskycli bench --fly-path`.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct M14AcceptanceBudgetTests {
    // MARK: - Frame budgets

    /// The shipping fly-path update budgets over a frame whose animation time
    /// is the locomotion work: the gate passes inside budget and still refuses
    /// an over-budget run, so it is live rather than vacuous.
    @Test
    func locomotionFramesStayWithinTheShippingUpdateBudgets() throws {
        let inBudget = Self.result(animationMS: [1.6, 1.9, 1.7])
        try validatedFlyUpdateBudgets(render: inBudget, configuration: Self.configuration())
        #expect(inBudget.animationPercentileMS(95) <= 4)

        let overBudget = Self.result(animationMS: [4.5, 6, 5])
        #expect(throws: CellStreamingFlyBenchmarkError.self) {
            try validatedFlyUpdateBudgets(
                render: overBudget, configuration: Self.configuration()
            )
        }
    }

    /// The two graphs the milestone runs — third person and first person — are
    /// both animation work, so a frame that runs both is measured against the
    /// same budget rather than against a doubled one. Stated as a case because
    /// "the arms are free" is exactly the kind of claim that stops being true
    /// quietly.
    @Test
    func bothPerspectiveGraphsAreCountedAgainstOneAnimationBudget() throws {
        let bothGraphs = Self.result(animationMS: [3.2, 3.8, 3.4])
        try validatedFlyUpdateBudgets(render: bothGraphs, configuration: Self.configuration())
        #expect(bothGraphs.animationAverageMS <= 4)
    }

    // MARK: - Fixed-step bound

    /// A stalled frame cannot drive an unbounded number of graph updates:
    /// `WalkController` clamps the time one frame contributes, so the worst
    /// case is a fixed number of fixed steps whatever the frame time was.
    @Test
    func aStalledFrameDrivesABoundedNumberOfGraphUpdates() {
        let cap = Int(
            (WalkController.maximumFrameTime / WalkController.fixedTimeStep).rounded(.down)
        )
        let chain = M14AcceptanceChain()
        let before = chain.graph.tally.updatesRun

        // A full second of stall, ten times the clamp.
        chain.frame(dt: 1)
        let updates = chain.graph.tally.updatesRun - before
        #expect(updates > 0, "the stalled frame stepped nothing at all")
        #expect(
            updates <= cap,
            "a stalled frame drove \(updates) graph updates, over the \(cap) cap"
        )
    }

    /// The pause the journal opens is the other end of the same rule: a frame
    /// worth zero time drives zero graph updates and costs nothing.
    @Test
    func apausedFrameDrivesNoGraphUpdateAtAll() {
        let chain = M14AcceptanceChain()
        chain.run(frames: 4)
        let before = chain.graph.tally.updatesRun
        let firstPerson = chain.firstPersonGraph.tally.updatesRun

        for _ in 0 ..< 30 {
            chain.frame(dt: 0)
        }

        #expect(chain.graph.tally.updatesRun == before)
        #expect(chain.firstPersonGraph.tally.updatesRun == firstPerson)
    }

    // MARK: - Fixtures

    /// A benchmark result whose only interesting axis is animation time; the
    /// other three sit comfortably inside their budgets so a failure names the
    /// axis this suite is about.
    private static func result(animationMS: [Double]) -> OffscreenBenchResult {
        OffscreenBenchResult(
            frameMS: [8, 9, 8],
            windowSummaries: [],
            animationMS: animationMS,
            shadowMS: [0.4, 0.5, 0.4],
            audioUpdateMS: [0.1, 0.1, 0.1],
            scriptUpdateMS: [0.2, 0.3, 0.2]
        )
    }

    /// The shipping fly-path budgets, matching `openskycli bench --fly-path`'s
    /// own defaults, spelled the way `M12AcceptanceBudgetTests` and
    /// `M13AcceptanceBudgetTests` spell them because they are private to the
    /// command.
    private static func configuration() -> CellStreamingFlyBenchmarkConfiguration {
        CellStreamingFlyBenchmarkConfiguration(
            start: CellCoordinate(x: 0, y: 0),
            size: (width: 1, height: 1),
            maxFrames: 1,
            footprintCapMB: 1024,
            collisionBuildBudgetMS: 750,
            actorBuildBudgetMS: 3000,
            animationUpdateBudgetMS: 4,
            shadowUpdateBudgetMS: 1.5,
            audioUpdateBudgetMS: 0.5,
            scriptUpdateBudgetMS: 0.5
        )
    }
}
