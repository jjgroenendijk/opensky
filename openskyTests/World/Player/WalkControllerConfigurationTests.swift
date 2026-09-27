// Controller behavior under injected movement tuning. Synthetic collision
// geometry only; no game content.

@testable import opensky
import simd
import Testing

struct WalkControllerConfigurationTests {
    @Test
    func injectedStepHeightChangesObstacleAcceptance() {
        let floor = quad(
            SIMD3(-200, -200, 0), SIMD3(200, -200, 0),
            SIMD3(200, 200, 0), SIMD3(-200, 200, 0)
        )
        let step = box(center: SIMD3(70, 0, 10), half: SIMD3(30, 100, 10))
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
        let query = collisionQuery([floor, step])
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

    private func collisionQuery(
        _ shapes: [StaticCollisionShape]
    ) -> WalkController.CollisionQuery {
        StaticCollisionSet(
            location: nil,
            shapes: shapes,
            stats: StaticCollisionStats()
        ).candidates
    }

    private func quad(
        _ first: SIMD3<Float>,
        _ second: SIMD3<Float>,
        _ third: SIMD3<Float>,
        _ fourth: SIMD3<Float>
    ) -> StaticCollisionShape {
        let vertices = [first, second, third, fourth]
        return StaticCollisionShape(
            reference: FormID(1),
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(vertices: vertices, indices: [0, 1, 2, 0, 2, 3]),
            bounds: ModelBounds.containing(vertices) ?? ModelBounds(min: .zero, max: .zero)
        )
    }

    private func box(center: SIMD3<Float>, half: SIMD3<Float>) -> StaticCollisionShape {
        StaticCollisionShape(
            reference: FormID(2),
            transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: half),
            bounds: ModelBounds(min: center - half, max: center + half)
        )
    }
}
