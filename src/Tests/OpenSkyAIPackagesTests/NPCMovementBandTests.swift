// A mover far from the camera steps less often and still arrives where its path ends.

@testable import OpenSkyAIPackages
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
struct NPCMovementBandTests {
    private let actor = ReferenceKey.plugin(name: "movement.esm", objectID: 1)

    /// Walks a 300-unit path in frames of 1/60 s with the camera at `viewer`.
    /// - Returns: how many steps the mover took, its band while walking, and the readout.
    private struct Walk {
        let steps: Int
        let band: UpdateBand?
        let arrived: Bool
    }

    private func walk(viewer: SIMD3<Float>?) -> Walk {
        let path = NPCMovementRuntimeTests.path(
            waypoints: [SIMD3(0, 0, 0), SIMD3(300, 0, 0)], target: SIMD3(300, 0, 0)
        )
        var runtime = NPCMovementRuntime()
        var steps = 0
        runtime.onDrive = { _ in steps += 1 }
        _ = runtime.start(NPCMovementRuntimeTests.start(actor: actor, path: path))
        var world = NPCMovementRuntimeTests.world()
        world.viewer = viewer
        var band: UpdateBand?
        for _ in 0 ..< 600 where runtime.activeMoverCount > 0 {
            runtime.advance(by: 1.0 / 60, world: world)
            band = runtime.movementBand(of: actor) ?? band
        }
        let arrived = runtime.readouts().first?.state == .arrived
        return Walk(steps: steps, band: band, arrived: arrived)
    }

    @Test func aFarMoverStepsLessOftenAndStillArrives() {
        let near = walk(viewer: SIMD3(0, 0, 0))
        let far = walk(viewer: SIMD3(0, 20000, 0))
        #expect(near.arrived)
        #expect(far.arrived)
        #expect(near.band == .full)
        #expect(far.band == .distant)
        #expect(far.steps * 3 <= near.steps)
    }

    @Test func aMoverWithoutAViewerStepsEveryFrame() {
        let unseen = walk(viewer: nil)
        let near = walk(viewer: SIMD3(0, 0, 0))
        #expect(unseen.steps == near.steps)
    }

    @Test func aStandingActorHasNoMovementBand() {
        let runtime = NPCMovementRuntime()
        #expect(runtime.movementBand(of: actor) == nil)
    }

    @Test func farWalkStepsAreLongerButFitTheFrameCap() {
        #expect(NPCMoverClocks.walkStepTime(in: .full) == PhysicsStep.fixedTimeStep)
        #expect(NPCMoverClocks.walkStepTime(in: .distant) > PhysicsStep.fixedTimeStep)
        #expect(NPCMoverClocks.longestBandStep < PhysicsStep.maximumFrameTime)
    }
}
