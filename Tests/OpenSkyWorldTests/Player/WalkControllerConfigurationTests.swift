// Controller behavior under injected movement tuning. Synthetic collision
// geometry only; no game content.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

struct WalkControllerConfigurationTests {
    @Test
    func injectedStepHeightChangesObstacleAcceptance() {
        let floor = DynamicBodyScene.quad(
            SIMD3(-200, -200, 0), SIMD3(200, -200, 0),
            SIMD3(200, 200, 0), SIMD3(-200, 200, 0)
        )
        let step = DynamicBodyScene.box(center: SIMD3(70, 0, 10), half: SIMD3(30, 100, 10))
        var lowCamera = camera()
        var highCamera = camera()
        var low = WalkController(
            cameraPosition: lowCamera.position,
            configuration: configuration(stepHeight: 12)
        )
        var high = WalkController(
            cameraPosition: highCamera.position,
            configuration: configuration(stepHeight: 24)
        )
        let query = DynamicBodyScene.candidateQuery([floor, step])
        drive(controller: &low, camera: &lowCamera, query: query)
        drive(controller: &high, camera: &highCamera, query: query)

        #expect(low.feetPosition.x < 17)
        #expect(high.feetPosition.x > 80)
        #expect(abs(high.feetPosition.z - 20) < 0.1)
    }

    private func drive(
        controller: inout WalkController,
        camera: inout FreeFlyCamera,
        query: @escaping WalkController.CollisionQuery
    ) {
        for _ in 0 ..< 60 {
            controller.update(
                camera: &camera,
                input: CameraInput(moveForward: 1, dt: WalkController.fixedTimeStep),
                sampleGround: { _ in nil },
                collisionQuery: query
            )
        }
    }

    private func camera() -> FreeFlyCamera {
        FreeFlyCamera(
            position: SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
    }

    private func configuration(stepHeight: Float) -> PlayerMovementConfiguration {
        PlayerMovementConfiguration(
            walkSpeed: MovementSetting(value: 180, source: "test"),
            runSpeed: MovementSetting(value: 360, source: "test"),
            stepHeight: MovementSetting(value: stepHeight, source: "test")
        )
    }
}
