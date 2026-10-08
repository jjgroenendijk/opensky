// The drawn capsule position blends between fixed steps, so a frame rate that
// does not divide the step rate still moves the view evenly.

@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

struct WalkControllerDrawnPositionTests {
    /// Three display frames per four steps: frames alternate between one and two steps.
    private static let frameTime = WalkController.fixedTimeStep * 0.75

    private static func flatGround(_: SIMD2<Float>) -> TerrainGroundSample? {
        TerrainGroundSample(height: 0, normal: SIMD3(0, 0, 1))
    }

    private static func walker() -> (WalkController, FreeFlyCamera) {
        var camera = FreeFlyCamera(
            position: SIMD3(0, 0, PlayerCapsule.standard.eyeHeight), yaw: 0, pitch: 0
        )
        var controller = WalkController(cameraPosition: camera.position)
        controller.update(
            camera: &camera,
            input: CameraInput(dt: WalkController.fixedTimeStep),
            sampleGround: flatGround
        )
        return (controller, camera)
    }

    private static func walk(
        _ controller: inout WalkController, camera: inout FreeFlyCamera, frames: Int
    ) -> [Float] {
        (0 ..< frames).map { _ in
            controller.update(
                camera: &camera,
                input: CameraInput(moveForward: 1, dt: frameTime),
                sampleGround: flatGround
            )
            return controller.drawnFeetPosition.x
        }
    }

    @Test func drawnPositionAdvancesEvenlyAtSteadySpeed() {
        var (controller, camera) = Self.walker()
        // The first frames blend away from standing still.
        _ = Self.walk(&controller, camera: &camera, frames: 8)
        let positions = Self.walk(&controller, camera: &camera, frames: 24)
        let advances = zip(positions.dropFirst(), positions).map { $0 - $1 }
        let expected = controller.configuration.walkSpeed.value * Self.frameTime
        for advance in advances {
            #expect(abs(advance - expected) < expected * 0.01)
        }
    }

    @Test func drawnPositionLagsTheStepByLessThanOneStep() {
        var (controller, camera) = Self.walker()
        _ = Self.walk(&controller, camera: &camera, frames: 8)
        let step = controller.configuration.walkSpeed.value * WalkController.fixedTimeStep
        let lag = controller.feetPosition.x - controller.drawnFeetPosition.x
        #expect(lag >= 0)
        #expect(lag <= step * 1.001)
    }

    @Test func resetDrawsAtTheNewPositionWithoutBlending() {
        var (controller, camera) = Self.walker()
        _ = Self.walk(&controller, camera: &camera, frames: 8)
        let target = SIMD3<Float>(5000, -200, 300)
        controller.reset(cameraPosition: target)
        #expect(controller.drawnCameraPosition == target)
        #expect(controller.drawnFeetPosition == controller.feetPosition)
    }
}
