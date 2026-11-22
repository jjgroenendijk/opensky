// The readout of a mover's newest walk step and of how often its walk was commanded.

@testable import OpenSkyAIPackages
import OpenSkyFormatsCore
import OpenSkyPhysics
import OpenSkyWorldInterface
import simd
import Testing

extension NPCMovementRuntimeTests {
    @Test
    func aWalkStepReportsItsMoveAndItsLongBody() throws {
        let path = Self.path(
            waypoints: [SIMD3(0, 0, 0), SIMD3(400, 0, 0)], target: SIMD3(400, 0, 0)
        )
        var start = Self.start(actor: actor, path: path)
        start.longBody = LongBodyShape(halfExtents: SIMD3(15.23, 62.27, 28.42))
        var runtime = NPCMovementRuntime()
        let started = runtime.start(start)
        #expect(started)
        runtime.advance(by: 0.1, world: Self.world())

        let readout = try #require(runtime.readouts().first)
        let step = try #require(readout.lastStep)
        #expect(step.steps > 0 && step.speed > 0)
        #expect(step.wanted.x > 0 && step.moved.x > 0)
        #expect(simd_length(step.bodyCorrection) < 0.001)
        #expect(readout.commands?.starts == 1 && readout.commands?.stops == 0)

        #expect(step.text.hasPrefix("wanted "))
        #expect(readout.commands?.text == "starts 1 stops 0")

        var blocked = step
        blocked.bodyPush = LongBodyPush()
        blocked.bodyPush?.part = .end(0)
        #expect(blocked.text.contains(" part end(0) resting "))

        let stopped = runtime.stop(actor)
        #expect(stopped)
        #expect(runtime.readouts().first?.commands?.stops == 1)
    }
}
