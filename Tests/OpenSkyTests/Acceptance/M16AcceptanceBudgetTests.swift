// AI acceptance, budget half. Movers, perception, and combat ride the shipping
// `animationUpdateBudgetMS`. `NPCMovementRuntime.maximumCPUTimeMillisecondsAtCap`
// is a 2 ms slice of that budget, checked to fit inside it. Three fixed-step
// clocks cap what a stalled frame can drive. Timings are synthetic.

import Foundation
@testable import OpenSkyCombat
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyPerception
@testable import OpenSkyPerceptionInterface
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

@MainActor
struct M16AcceptanceBudgetTests {
    // MARK: - Frame budgets

    /// The shipping fly-path update budgets over a frame whose animation time is
    /// the AI scene's: the player's two graphs, the mover's gait clips and the
    /// skinning they feed. The gate passes inside budget and still refuses an
    /// over-budget run, so it is live rather than vacuous.
    @Test
    func aiFramesStayWithinTheShippingUpdateBudgets() throws {
        let inBudget = Self.result(animationMS: [2.6, 3.1, 2.8])
        try validatedFlyUpdateBudgets(render: inBudget, configuration: Self.configuration())
        #expect(inBudget.animationPercentileMS(95) <= 4)

        let overBudget = Self.result(animationMS: [4.5, 6, 5])
        #expect(throws: CellStreamingFlyBenchmarkError.self) {
            try validatedFlyUpdateBudgets(
                render: overBudget, configuration: Self.configuration()
            )
        }
    }

    /// Item 16.4's mover slice is carved out of the same animation budget rather
    /// than added beside it. Stated as a case because "the AI has its own two
    /// milliseconds" is exactly the kind of claim that quietly becomes a second
    /// budget nobody reconciles.
    @Test
    func theMoverSliceFitsInsideTheShippingAnimationBudget() {
        let slice = NPCMovementRuntime.maximumCPUTimeMillisecondsAtCap
        #expect(slice > 0)
        #expect(
            slice <= Self.configuration().animationUpdateBudgetMS,
            "the mover slice no longer fits inside the animation budget it is carved from"
        )
    }

    // MARK: - Fixed-step bounds

    /// A stalled frame cannot drive an unbounded day. Each of the three
    /// fixed-step clocks the frame runs caps its own contribution, so the worst
    /// case is a fixed number of steps whatever the frame time was.
    @Test
    func aStalledFrameDrivesABoundedNumberOfStepsInEveryClock() throws {
        let chain = try M16AcceptanceChain()
        chain.setHour(9)
        chain.setGuardHostile(true)
        chain.playerFeet = chain.guardFeet + SIMD3(60, 0, 0)
        chain.run(frames: 400) { chain.guardDetection.state == .detected }

        // A full second of stall, many times either fixed step.
        let combatSteps = chain.combat.advance(by: 1)
        let perceptionSteps = chain.perception.advance(by: 1)

        #expect(combatSteps > 0, "the stalled frame stepped no combat at all")
        #expect(combatSteps <= CombatLoopRuntime.maximumStepsPerAdvance)
        #expect(perceptionSteps > 0, "the stalled frame stepped no perception at all")
        #expect(perceptionSteps <= PerceptionRuntime.maximumStepsPerAdvance)
    }

    /// The mover's own bound is a distance rather than a step count: it runs on
    /// the delta it is given, so a stalled frame must not teleport an actor down
    /// its corridor. Measured as travel against what its own gait could cover.
    @Test
    func aStalledFrameDoesNotTeleportAMoverDownItsCorridor() throws {
        let chain = try M16AcceptanceChain()
        #expect(chain.moveGuard(to: M16AcceptanceChain.bedPosition) == .started)
        chain.run(frames: 20)
        let before = chain.guardFeet

        chain.frame(dt: 1)

        let travelled = simd_distance(chain.guardFeet, before)
        let ceiling = PlayerMovementConfiguration.synthetic.runSpeed.value
        #expect(travelled >= 0)
        #expect(
            travelled <= ceiling,
            "a stalled frame moved the guard \(travelled) units, over its own run speed"
        )
    }

    /// The other end of the same rule: a frame worth zero time advances no
    /// mover, no detection level and no fight.
    @Test
    func apausedFrameDrivesNothingAtAll() throws {
        let chain = try M16AcceptanceChain()
        chain.setHour(9)
        chain.setGuardHostile(true)
        chain.playerFeet = chain.guardFeet + SIMD3(60, 0, 0)
        #expect(chain.moveGuard(to: M16AcceptanceChain.bedPosition) == .started)
        chain.run(frames: 40)

        let feet = chain.guardFeet
        let level = chain.guardDetection.level
        let phase = chain.combat.phase(of: M16AcceptanceChain.guardKey)
        for _ in 0 ..< 30 {
            chain.frame(dt: 0)
        }

        #expect(chain.guardFeet == feet)
        #expect(chain.guardDetection.level == level)
        #expect(chain.combat.phase(of: M16AcceptanceChain.guardKey) == phase)
    }

    // MARK: - Crowd bounds

    /// The crowd cap is what makes the mover slice a fixed cost rather than a
    /// per-NPC one. The ninth simultaneous request is refused, and refusing it
    /// is an answer the panel prints rather than a silent drop.
    @Test
    func theCrowdCapRefusesTheNinthMoverAndSaysSo() {
        var runtime = NPCMovementRuntime()
        let path = M16AcceptanceBudgetTests.straightPath()
        let cap = NPCMovementRuntime.maximumSimultaneousMovers
        for index in 0 ..< cap {
            let started = runtime.start(Self.start(index: index, path: path))
            #expect(started, "the cap refused mover \(index + 1) of \(cap)")
        }
        let ninth = runtime.start(Self.start(index: cap, path: path))
        #expect(!ninth)
        #expect(runtime.activeMoverCount == cap)

        let refused = AINavigationReadout.moveResultText(.moverCapReached, actor: "Guard")
        #expect(refused.contains("the mover cap is full"))
    }

    // MARK: - Fixtures

    private static func straightPath() -> NavigationPath {
        NavigationPath(
            waypoints: [SIMD3(0, 0, 0), SIMD3(400, 0, 0)],
            doorCrossings: [],
            stats: NavigationPathStats(nodesExpanded: 1, corridorTriangleCount: 1),
            corridor: [],
            cellSequences: [:],
            target: SIMD3(400, 0, 0)
        )
    }

    private static func start(index: Int, path: NavigationPath) -> NPCMoveStart {
        NPCMoveStart(
            actor: .generated(UInt64(index + 1)),
            formID: FormID(UInt32(0x2000 + index)),
            placement: PlacedReference.Placement(position: .zero, rotation: .zero),
            scale: 1,
            capsule: .standard,
            configuration: .synthetic,
            path: path
        )
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
    /// own defaults, spelled the way `M14AcceptanceBudgetTests` and
    /// `M15AcceptanceBudgetTests` spell them because they are private to the
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
