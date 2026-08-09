// M15 acceptance, budget half (issue #198): the fight is held to the per-frame
// budgets that already exist, and adds no set of numbers of its own.
//
// The constraint M13 put on M14 and M14 put on M15: combat adds more graph work
// and a physics step to the same frame, so it is measured against the shipping
// `animationUpdateBudgetMS` the fly-path validator already enforces and against
// the same benchmark configuration `openskycli bench --fly-path` uses — not
// against a second copy of the numbers.
//
// The other half of the claim is that the fight is bounded by construction.
// Four fixed-step clocks run inside one frame — the walk controller's, the
// combat loop's, the ragdoll registry's and the dynamic body registry's — and
// every one of them caps what a single stalled frame can drive. A gate that
// only measured a healthy frame would say nothing about the frame that stalls,
// and the stall is where a combat scene actually falls over.
//
// The timings are synthetic, as they are throughout `CellStreamingFlyPathTests`:
// these cases pin the gate's behaviour, not this machine's speed. Measured
// timings against the real install come from `openskycli bench --fly-path`.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct M15AcceptanceBudgetTests {
    // MARK: - Frame budgets

    /// The shipping fly-path update budgets over a frame whose animation time
    /// is the combat scene's: two locomotion graphs, the opponent's, and the
    /// skinning they feed. The gate passes inside budget and still refuses an
    /// over-budget run, so it is live rather than vacuous.
    @Test
    func combatFramesStayWithinTheShippingUpdateBudgets() throws {
        let inBudget = Self.result(animationMS: [2.4, 2.9, 2.6])
        try validatedFlyUpdateBudgets(render: inBudget, configuration: Self.configuration())
        #expect(inBudget.animationPercentileMS(95) <= 4)

        let overBudget = Self.result(animationMS: [4.5, 6, 5])
        #expect(throws: CellStreamingFlyBenchmarkError.self) {
            try validatedFlyUpdateBudgets(
                render: overBudget, configuration: Self.configuration()
            )
        }
    }

    /// The combat scene's extra graph — the opponent's — rides the same
    /// animation budget the two perspective graphs already ride, rather than a
    /// budget of its own. Stated as a case because "one more actor is free" is
    /// exactly the kind of claim that stops being true quietly.
    @Test
    func theOpponentGraphIsCountedAgainstTheSameAnimationBudget() throws {
        let threeGraphs = Self.result(animationMS: [3.4, 3.9, 3.6])
        try validatedFlyUpdateBudgets(render: threeGraphs, configuration: Self.configuration())
        #expect(threeGraphs.animationAverageMS <= 4)
    }

    // MARK: - Fixed-step bounds

    /// A stalled frame cannot drive an unbounded fight. Each of the four
    /// fixed-step clocks the frame runs caps its own contribution, so the worst
    /// case is a fixed number of steps whatever the frame time was.
    @Test
    func aStalledFrameDrivesABoundedNumberOfStepsInEveryClock() throws {
        let chain = try M15AcceptanceChain()
        chain.capturePointer()
        chain.press(.keyR)
        chain.run(frames: 60) { chain.melee.state.drawState == .drawn }
        chain.combat.setHostility(.hostile, on: Chain.opponent)
        chain.settleGraph()

        let graphCap = Int(
            (WalkController.maximumFrameTime / WalkController.fixedTimeStep).rounded(.down)
        )
        let updates = chain.graph.tally.updatesRun
        let contacts = chain.combat.behaviors[Chain.opponent]?.contactCount ?? 0

        // A full second of stall, ten times the walk controller's clamp.
        chain.frame(dt: 1)

        let drove = chain.graph.tally.updatesRun - updates
        #expect(drove > 0, "the stalled frame stepped nothing at all")
        #expect(drove <= graphCap, "a stalled frame drove \(drove) graph updates, over \(graphCap)")
        // The combat loop's own cap is the tighter of the two, and it is the
        // one that decides how many blows one stalled frame can land.
        #expect(
            (chain.combat.behaviors[Chain.opponent]?.contactCount ?? 0) - contacts
                <= CombatLoopRuntime.maximumStepsPerAdvance
        )
    }

    /// The two physics registries share the walk controller's clamp, so a
    /// stalled frame integrates a bounded amount of time rather than teleporting
    /// a crate through the floor. Measured as travel: an unbounded step would
    /// move a falling body by a second of gravity in one go.
    @Test
    func aStalledFrameIntegratesABoundedAmountOfPhysics() throws {
        let chain = try M15AcceptanceChain()
        chain.run(frames: 2)
        let start = try #require(chain.crateBody)
        let before = start.position.z
        let speed = abs(start.linearVelocity.z)

        chain.frame(dt: 1)

        let after = try #require(chain.crateBody?.position.z)
        let fell = before - after
        // The clamp is `maximumFrameTime`, so the furthest the body can travel
        // in one frame is what it covers under gravity over that clamp, from
        // the speed it already had. An unclamped step would cover a whole
        // second of the same motion, which is an order of magnitude further.
        let clamp = WalkController.maximumFrameTime
        let ceiling = speed * clamp + 0.5 * WalkController.gravity * clamp * clamp
        let unclamped = speed + 0.5 * WalkController.gravity
        #expect(fell >= 0)
        #expect(fell <= ceiling + 1, "a stalled frame fell \(fell) units, over \(ceiling)")
        #expect(fell < unclamped, "the stalled frame integrated the whole second")
    }

    /// The pause the journal opens is the other end of the same rule: a frame
    /// worth zero time drives no graph update, no fight step, and no physics.
    @Test
    func apausedFrameDrivesNothingAtAll() throws {
        let chain = try M15AcceptanceChain()
        chain.capturePointer()
        chain.run(frames: 8)
        let updates = chain.graph.tally.updatesRun
        let opponentUpdates = chain.opponentGraph.tally.updatesRun
        let crate = chain.crateBody?.position

        for _ in 0 ..< 30 {
            chain.frame(dt: 0)
        }

        #expect(chain.graph.tally.updatesRun == updates)
        #expect(chain.opponentGraph.tally.updatesRun == opponentUpdates)
        #expect(chain.crateBody?.position == crate)
    }

    // MARK: - Stress, inside the acceptance suite's bounds

    /// The 15.2 clutter stress, run here rather than described: a body shoved
    /// and dropped over a long run stays finite, stays above the floor, and
    /// loses energy rather than gaining it. No NaN, no tunnelling, no energy
    /// growth.
    @Test
    func theClutterStressStaysFiniteAndLosesEnergy() throws {
        let chain = try M15AcceptanceChain()
        chain.run(frames: 4)
        let start = try #require(chain.crateBody)
        let startEnergy = Self.energy(of: start)

        #expect(
            chain.run(frames: 900) { chain.crateBody?.isSleeping == true },
            "the crate never came to rest"
        )

        let settled = try #require(chain.crateBody)
        #expect(settled.position.isFiniteVector)
        #expect(settled.linearVelocity.isFiniteVector)
        #expect(settled.position.z > M15AcceptanceWorld.floorHeight, "the crate tunnelled")
        #expect(Self.energy(of: settled) < startEnergy, "the body gained energy")
        #expect(chain.streamer.dynamicBodies.statsSnapshot.recoveredBodyCount == 0)
    }

    /// The 15.6 repeated-collapse stress: the same corpse is ragdolled, cleared
    /// and ragdolled again, and every collapse converges to a settled pose with
    /// no violated limits and no recovered bones.
    @Test
    func repeatedCollapsesConvergeEveryTime() throws {
        let chain = try M15AcceptanceChain()
        for round in 1 ... 3 {
            #expect(chain.ragdolls.trigger(Chain.opponent), "round \(round) spawned no ragdoll")
            #expect(
                chain.run(frames: 2000) {
                    chain.ragdolls.world.statsSnapshot.settledRagdollCount == 1
                },
                "round \(round) never settled"
            )
            let stats = chain.ragdolls.world.statsSnapshot
            #expect(stats.jointViolationCount == 0, "round \(round) left limits violated")
            #expect(stats.recoveredBodyCount == 0, "round \(round) recovered a bone")
            chain.ragdolls.reset()
            #expect(chain.ragdolls.world.ragdollCount == 0)
        }
    }

    private typealias Chain = M15AcceptanceChain

    // MARK: - Fixtures

    /// Kinetic plus gravitational potential energy of one body, the quantity
    /// the stability gate watches: it may fall, because damping and friction
    /// take energy out, but it must never climb.
    private static func energy(of body: DynamicBody) -> Float {
        let mass = body.definition.mass
        let linear = 0.5 * mass * simd_length_squared(body.linearVelocity)
        let angular = 0.5 * mass * simd_length_squared(body.angularVelocity)
        return linear + angular
            + mass * WalkController.gravity
            * (body.position.z - M15AcceptanceWorld.floorHeight)
    }

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
    /// own defaults, spelled the way `M13AcceptanceBudgetTests` and
    /// `M14AcceptanceBudgetTests` spell them because they are private to the
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
