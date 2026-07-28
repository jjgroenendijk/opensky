// Walk benchmark state-machine gates over synthetic values only. These pin
// the real driver's fall-through, avoidance, and timeout thresholds without
// Metal or game data.

@testable import opensky
import simd
import Testing

struct CellStreamingWalkDriverTests {
    @Test
    func fallThroughRequiresSixteenAirborneFramesAndCapsuleHeightDrop() throws {
        var state = WalkBenchmarkControllerState()
        let phase = WalkBenchmarkPhase.walkExterior(2)
        let grounded = WalkBenchmarkControllerSnapshot(
            position: SIMD3<Float>(10, 20, 100),
            isGrounded: true,
            hasUnresolvedPenetration: false
        )
        try state.validate(phase: phase, snapshot: grounded)

        let lowAirborne = WalkBenchmarkControllerSnapshot(
            position: SIMD3<Float>(10, 20, 100 - PlayerCapsule.standard.height - 1),
            isGrounded: false,
            hasUnresolvedPenetration: false
        )
        for _ in 0 ..< 15 {
            try state.validate(phase: phase, snapshot: lowAirborne)
        }
        #expect(state.airborneFrames == 15)

        do {
            try state.validate(phase: phase, snapshot: lowAirborne)
            Issue.record("expected the sixteenth low airborne frame to fail")
        } catch let error as CellStreamingWalkBenchmarkError {
            guard case let .fallThrough(description, position) = error else {
                Issue.record("expected fallThrough, got \(error)")
                return
            }
            #expect(description == phase.description)
            #expect(position == lowAirborne.position)
        }
    }

    @Test
    func fallThroughRequiresBothAirborneAndHeightThresholds() throws {
        var state = WalkBenchmarkControllerState()
        let phase = WalkBenchmarkPhase.crossInterior
        try state.validate(
            phase: phase,
            snapshot: WalkBenchmarkControllerSnapshot(
                position: SIMD3<Float>(0, 0, 50),
                isGrounded: true,
                hasUnresolvedPenetration: false
            )
        )
        let stillWithinCapsuleHeight = WalkBenchmarkControllerSnapshot(
            position: SIMD3<Float>(0, 0, 50 - PlayerCapsule.standard.height),
            isGrounded: false,
            hasUnresolvedPenetration: false
        )
        for _ in 0 ..< 20 {
            try state.validate(phase: phase, snapshot: stillWithinCapsuleHeight)
        }
        #expect(state.airborneFrames == 20)
    }

    @Test
    func stalledNavigationStartsAlternatingAvoidanceOnTwentiethFrame() {
        var state = WalkBenchmarkNavigationState()
        state.update(distance: 100, routeIndex: 2)
        for _ in 0 ..< 19 {
            state.update(distance: 100, routeIndex: 2)
        }
        #expect(state.stalledFrames == 19)
        #expect(state.avoidanceFrames == 0)

        state.update(distance: 100, routeIndex: 2)
        #expect(state.stalledFrames == 0)
        #expect(state.avoidanceFrames == 36)
        #expect(state.avoidanceAttempt == 1)
        #expect(state.avoidanceDirection == 1)

        state.avoidanceFrames = 0
        for _ in 0 ..< 20 {
            state.update(distance: 100, routeIndex: 2)
        }
        #expect(state.avoidanceAttempt == 2)
        #expect(state.avoidanceDirection == -1)
    }

    @Test
    func timeoutFailsAtLimitWithCurrentPhaseAndPosition() throws {
        let phase = WalkBenchmarkPhase.waitInterior
        let position = SIMD3<Float>(1, 2, 3)
        try WalkBenchmarkStateMachine.validateTimeout(
            phaseFrames: 119,
            limit: 120,
            phase: phase,
            position: position
        )

        do {
            try WalkBenchmarkStateMachine.validateTimeout(
                phaseFrames: 120,
                limit: 120,
                phase: phase,
                position: position
            )
            Issue.record("expected the frame limit to time out")
        } catch let error as CellStreamingWalkBenchmarkError {
            guard case let .routeTimedOut(description, actualPosition) = error else {
                Issue.record("expected routeTimedOut, got \(error)")
                return
            }
            #expect(description == phase.description)
            #expect(actualPosition == position)
        }
    }
}
