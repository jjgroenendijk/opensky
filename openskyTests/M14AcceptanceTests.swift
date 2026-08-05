// M14 acceptance (issue #191): one continuous route, driven by key events,
// through every locomotion state the milestone claims.
//
// The gate statement in one run: idle, walk, run, sprint, jump, land, sneak and
// swim are all entered; root motion resolves through collision on flat ground,
// a slope and water; the route crosses a streaming boundary and a door round
// trip and comes back with its position and its movement state intact; a
// zero-length frame advances the simulation by nothing; and the first-person
// graph reaches the same states from the same input as the third-person one.
//
// Every step asserts what the engine holds, not just that the call returned:
// which state the machine entered, which source moved the capsule, which cell
// the streamer attached, and what the bridge told the graph. The pixel half is
// `M14AcceptanceRenderTests` and the panel half is `M14AcceptancePanelTests`;
// both are gated, and everything here runs on a device-less runner with no
// install.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct M14AcceptanceTests {
    private typealias Chain = M14AcceptanceChain
    private typealias World = M14AcceptanceWorld
    private typealias State = M14AcceptanceFixture.State

    // MARK: - The route

    /// The gate itself. One session walks the whole route and every step is
    /// checked before the next one runs, so a failure names the step rather
    /// than leaving an end state to reverse-engineer.
    @Test("one route drives every locomotion state through the shipping input path")
    func theRouteRunsEveryLocomotionState() throws {
        let chain = Chain()

        try Self.standStill(chain)
        try Self.walkForward(chain)
        try Self.runUpTheSlope(chain)
        try Self.sprintAndJump(chain)
        try Self.swimTheBasin(chain)
        try Self.crossTheCellBoundary(chain)
        try Self.sneakThroughTheDoor(chain)
        try Self.pauseAdvancesNothing(chain)
        Self.expectEveryStateWasEntered(chain)
    }

    // MARK: - Steps

    /// Step 1 — nobody is pressing anything. The graph sits in its start state
    /// and the planner asks for no horizontal motion at all.
    private static func standStill(_ chain: Chain) throws {
        chain.run(frames: 10)

        #expect(
            chain.currentState == State.idle.name,
            "the graph did not come up in its start state"
        )
        #expect(chain.status.motionSource == .idle)
        #expect(chain.status.lastPlan.horizontalDisplacement == SIMD2<Float>())
        #expect(chain.controller.isGrounded)
        #expect(chain.feetPosition.z.isApproximately(World.flatHeight))
    }

    /// Step 2 — the walk key goes down on the real view. `moveStart` reaches
    /// the graph, the walk gait resolves, and the capsule travels at the
    /// configured walk speed rather than at whatever the clip does.
    private static func walkForward(_ chain: Chain) throws {
        let start = chain.feetPosition.x
        chain.press(.keyW)
        chain.run(frames: 60)

        #expect(chain.currentState == State.walk.name)
        #expect(chain.status.gait == .walk)
        #expect(chain.status.motionSource == .configuredSpeed)
        let travelled = chain.feetPosition.x - start
        let expected = PlayerMovementConfiguration.synthetic.walkSpeed.value
        #expect(travelled > expected * 0.9)
        #expect(travelled < expected * 1.1)
        #expect(chain.status.raisedEvents.contains(LocomotionGraphNames.moveStart))
        // The graph is a consumer of the movement variables, not the source of
        // the movement: vanilla clips carry no extracted motion and neither do
        // the synthetic ones.
        #expect(chain.status.rootMotionDistance == 0)
        #expect(chain.status.configuredSpeedDistance > 0)
    }

    /// Step 3 — the player stops, holds the run modifier, and sets off again.
    /// The same `moveStart` edge lands in `Run` this time because `Speed` is
    /// over the machine's threshold, and the capsule climbs the slope.
    private static func runUpTheSlope(_ chain: Chain) throws {
        chain.release(.keyW)
        chain.run(frames: 10)
        #expect(
            chain.currentState == State.idle.name,
            "releasing the walk key did not stop the graph"
        )

        chain.setModifiers(run: true, sprint: false)
        chain.press(.keyW)
        chain.run(frames: 10)
        #expect(chain.currentState == State.run.name)
        #expect(chain.status.gait == .run)

        #expect(chain.run(toX: 2100), "the run never reached the plateau")
        #expect(chain.controller.isGrounded, "the capsule left the slope")
        #expect(chain.feetPosition.z.isApproximately(World.plateauHeight, within: 2))
        #expect(chain.currentState == State.run.name)
    }

    /// Step 4 — sprint along the plateau, then stop and jump on the spot.
    ///
    /// The jump is taken standing rather than at a sprint because a sprinting
    /// jump from this plateau clears the whole basin, and a route that flies
    /// over the water would not have swum in it. Landing is the controller's
    /// observation and reaches the graph as a state of its own.
    private static func sprintAndJump(_ chain: Chain) throws {
        chain.setModifiers(run: true, sprint: true)
        chain.run(frames: 6)
        #expect(chain.currentState == State.sprint.name)
        #expect(chain.status.gait == .sprint)

        chain.release(.keyW)
        chain.setModifiers(run: false, sprint: false)
        chain.run(frames: 10)
        let standing = chain.feetPosition

        chain.press(.space)
        #expect(
            chain.run(frames: 40) { !chain.controller.isGrounded },
            "the jump never left the ground"
        )
        #expect(chain.currentState == State.jump.name)
        #expect(chain.status.lastPlan.jumpImpulse == nil, "the impulse outlived its one step")

        #expect(chain.run(frames: 240) { chain.controller.isGrounded }, "the jump never landed")
        chain.run(frames: 2)
        #expect(chain.currentState == State.land.name)
        #expect(chain.status.raisedEvents.contains(LocomotionGraphNames.jumpUp))
        #expect(chain.status.raisedEvents.contains(LocomotionGraphNames.jumpLand))
        // A standing jump goes straight up: the capsule comes back down where
        // it took off, which is the collision path resolving vertical motion on
        // its own while the planner asked for none.
        #expect(chain.feetPosition.isApproximately(standing, within: 2))
    }

    /// Step 5 — down the bank into water deep enough to swim in, across the
    /// basin, and out the far side.
    private static func swimTheBasin(_ chain: Chain) throws {
        chain.setModifiers(run: true, sprint: false)
        chain.press(.keyW)
        #expect(
            chain.run(frames: 2000) { chain.status.isSwimming },
            "the player never started swimming"
        )
        #expect(chain.currentState == State.swim.name)
        #expect(chain.status.gait == .swim)
        #expect(chain.controller.isSwimming)
        // The capsule is held at the surface rather than sunk to the floor.
        #expect(chain.feetPosition.z > World.basinHeight)
        #expect(chain.feetPosition.z < World.waterSurface)

        #expect(
            chain.run(frames: 3000) { !chain.status.isSwimming },
            "the player never left the water"
        )
        #expect(chain.status.raisedEvents.contains(LocomotionGraphNames.swimStart))
        #expect(chain.status.raisedEvents.contains(LocomotionGraphNames.swimStop))
        #expect(chain.run(toX: 3200), "the far bank was never climbed")
        #expect(chain.feetPosition.z.isApproximately(World.plateauHeight, within: 2))
    }

    /// Step 6 — the run east crosses into the next cell. The streamer attaches
    /// it while the player keeps moving, and neither the capsule nor the graph
    /// state is disturbed by the swap.
    private static func crossTheCellBoundary(_ chain: Chain) throws {
        let stateBefore = chain.currentState
        #expect(chain.attachedLocations.locations == [.exterior(CellCoordinate(x: 0, y: 0))])

        #expect(chain.run(toX: Chain.doorPosition.x - 120), "the route never reached the door")
        #expect(chain.attachedLocations.locations.contains(.exterior(CellCoordinate(x: 1, y: 0))))
        #expect(chain.currentState == stateBefore, "the cell swap changed the locomotion state")
        #expect(chain.status.gait == .run)
        #expect(chain.controller.isGrounded)
    }

    /// Step 7 — sneak, then use the door, walk the interior, and come back. The
    /// sneak toggle is a mode rather than a held key, so it has to survive the
    /// round trip, and the capsule has to come back where it started.
    private static func sneakThroughTheDoor(_ chain: Chain) throws {
        // Stopping first, because one update fires one transition: a frame that
        // both stopped and started sneaking would raise `moveStop` and
        // `SneakStart` together and the machine would take exactly one of them.
        chain.release(.keyW)
        chain.setModifiers(run: false, sprint: false)
        chain.run(frames: 6)
        chain.press(.keyC)
        chain.run(frames: 10)
        #expect(chain.currentState == State.sneak.name)
        #expect(chain.status.gait == .sneak)

        let exterior = chain.feetPosition
        chain.pressUseKey(toward: Chain.doorPosition)
        chain.completeDoorTransition(
            from: Chain.doorReference,
            to: Chain.interiorDoorReference,
            at: Chain.interiorPosition,
            interior: true
        )
        #expect(chain.streamer.isInterior)
        #expect(chain.attachedLocations.locations.last == .interior(Chain.interiorCell))
        #expect(chain.feetPosition.isApproximately(Chain.interiorPosition))

        // The interior is walkable: the same keys move the same capsule there.
        chain.press(.keyW)
        chain.run(frames: 30)
        #expect(chain.feetPosition.x > Chain.interiorPosition.x)
        chain.release(.keyW)
        chain.run(frames: 10)

        chain.pressUseKey(toward: Chain.interiorPosition)
        chain.completeDoorTransition(
            from: Chain.interiorDoorReference,
            to: Chain.doorReference,
            at: exterior,
            interior: false
        )
        #expect(!chain.streamer.isInterior)
        #expect(chain.feetPosition.isApproximately(exterior))
        // Sneak is a mode and deliberately survives a teleport, so the first
        // step back outside resolves the sneak gait again and the graph
        // re-enters its sneak state.
        chain.run(frames: 6)
        #expect(chain.status.gait == .sneak)
        #expect(chain.currentState == State.sneak.name)
    }

    /// Step 8 — the journal-open pause. A zero-length frame plans nothing,
    /// writes nothing, raises nothing and updates no graph, so opening a menu
    /// can neither move the player nor fire a behavior event.
    private static func pauseAdvancesNothing(_ chain: Chain) throws {
        let position = chain.feetPosition
        let status = chain.status
        let updates = chain.graph.tally.updatesRun

        for _ in 0 ..< 20 {
            chain.frame(dt: 0)
        }

        #expect(chain.feetPosition == position)
        #expect(chain.status == status, "a paused frame changed the locomotion status")
        #expect(chain.graph.tally.updatesRun == updates, "a paused frame stepped the graph")
        #expect(chain.status.lastPlan == .still)
    }

    // MARK: - The claim

    /// Every state the milestone names was entered by the route, and the
    /// first-person graph followed the third-person one through all of them.
    private static func expectEveryStateWasEntered(_ chain: Chain) {
        let visited = Set(chain.visitedStates)
        for state in State.allCases {
            #expect(visited.contains(state.name), "the route never entered \(state.name)")
        }
        #expect(
            chain.firstPersonVisitedStates == chain.visitedStates,
            "the two perspectives took different paths through the same graph"
        )
        // Same input, different perspective: the one variable that is meant to
        // differ does, and every other name resolved on both.
        #expect(
            chain.graph.variable(named: LocomotionGraphNames.isFirstPerson) == .bool(false)
        )
        #expect(
            chain.firstPersonGraph.variable(named: LocomotionGraphNames.isFirstPerson)
                == .bool(true)
        )
        #expect(chain.status.missingVariables.isEmpty)
        #expect(chain.status.missingEvents.isEmpty)
        #expect(chain.status.firstPersonMissingVariables.isEmpty)
        #expect(chain.status.firstPersonMissingEvents.isEmpty)
        // Nothing in the route reached a class the evaluator has no semantics
        // for: the synthetic graph is made only of shapes OpenSky implements,
        // so a gap here would be a regression rather than an owed feature.
        #expect(chain.graph.tally.gapTotal == 0)
    }

    // MARK: - Determinism

    /// Two runs of the same route produce the same trace, which is what makes
    /// every number above evidence rather than a sample.
    @Test("the route is deterministic")
    func theRouteRepeatsExactly() throws {
        let first = try Self.shortRoute()
        let second = try Self.shortRoute()
        #expect(first.states == second.states)
        #expect(first.position == second.position)
        #expect(first.status == second.status)
    }

    /// A shortened route — walk, run, jump, sneak — run twice for the
    /// determinism claim. The full route is driven once by the gate above; what
    /// this needs is repetition, not length.
    private static func shortRoute() throws -> M14RouteTrace {
        let chain = Chain()
        chain.run(frames: 5)
        chain.press(.keyW)
        chain.run(frames: 30)
        chain.setModifiers(run: true, sprint: false)
        chain.release(.keyW)
        chain.run(frames: 5)
        chain.press(.keyW)
        chain.run(frames: 30)
        chain.press(.space)
        chain.run(frames: 60)
        chain.press(.keyC)
        chain.run(frames: 10)
        return M14RouteTrace(
            states: chain.visitedStates, position: chain.feetPosition, status: chain.status
        )
    }
}

/// What one run of the route left behind, compared whole between two runs.
private struct M14RouteTrace {
    let states: [String]
    let position: SIMD3<Float>
    let status: LocomotionStatus
}

extension Float {
    /// Comparison for positions the simulation resolves rather than sets, where
    /// exact equality would be pinning float noise.
    func isApproximately(_ other: Float, within tolerance: Float = 0.5) -> Bool {
        abs(self - other) <= tolerance
    }
}

extension SIMD3<Float> {
    func isApproximately(_ other: SIMD3<Float>, within tolerance: Float = 0.5) -> Bool {
        simd_length(self - other) <= tolerance
    }
}
