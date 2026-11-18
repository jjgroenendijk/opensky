// The slope rule on the touched surface only: terrain and meshes alike, a mesh floor over
// steep terrain, the ground search, and gravity by phase. Synthetic ground, no game assets.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyPhysics
@testable import OpenSkyPlayer
@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
import simd
import Testing

struct WalkControllerSlopeTests {
    @Test
    func terrainOf46DegreesIsWalkedUp() {
        let slope = Self.terrainSlope(degrees: 46)
        var camera = CapsuleCollisionTests.camera(feet: SIMD3(-40, 0, 0))
        var controller = WalkController(cameraPosition: camera.position)
        Self.walk(&controller, camera: &camera, forward: 1, steps: 240, ground: slope)

        #expect(controller.feetPosition.x > 60)
        #expect(controller.feetPosition.z > 60)
        #expect(controller.isGrounded)
    }

    @Test
    func terrainOf48DegreesSlidesTheWalkerBackDown() {
        let slope = Self.terrainSlope(degrees: 48)
        let start = SIMD3<Float>(200, 0, Self.height(at: 200, degrees: 48))
        var camera = CapsuleCollisionTests.camera(feet: start)
        var controller = WalkController(cameraPosition: camera.position)
        Self.walk(&controller, camera: &camera, forward: 1, steps: 120, ground: slope)

        #expect(controller.feetPosition.z < start.z - 50)
        #expect(controller.feetPosition.x < start.x)
        // It slides on the face; it does not sink into it.
        let below = Self.height(at: controller.feetPosition.x, degrees: 48)
        #expect(controller.feetPosition.z >= below - 1)
    }

    @Test
    func meshOf46DegreesIsWalkedUp() {
        let ramp = Self.meshSlope(degrees: 46)
        var camera = CapsuleCollisionTests.camera(feet: SIMD3(-40, 0, 1))
        var controller = WalkController(cameraPosition: camera.position)
        Self.walk(
            &controller, camera: &camera, forward: 1, steps: 120,
            query: DynamicBodyScene.candidateQuery(ramp)
        )

        #expect(controller.feetPosition.x > 60)
        #expect(controller.feetPosition.z > 60)
        #expect(controller.isGrounded)
    }

    @Test
    func meshOf48DegreesSlidesTheWalkerBackDown() {
        let ramp = Self.meshSlope(degrees: 48)
        let start = SIMD3<Float>(200, 0, Self.height(at: 200, degrees: 48) + 20)
        var camera = CapsuleCollisionTests.camera(feet: start)
        var controller = WalkController(cameraPosition: camera.position)
        Self.walk(
            &controller, camera: &camera, forward: 1, steps: 120,
            query: DynamicBodyScene.candidateQuery(ramp)
        )

        #expect(controller.feetPosition.z < start.z - 50)
        #expect(controller.feetPosition.x < start.x)
        #expect(!controller.hasUnresolvedPenetration)
    }

    @Test
    func aMeshFloorOverSteepTerrainIsWalkedAsTheFloor() {
        // A dock 100 units up over a 60-degree bank that stays under it.
        let dock = DynamicBodyScene.box(center: SIMD3(100, 0, 90), half: SIMD3(300, 100, 10))
        let bank: WalkController.GroundSampler = { position in
            let rise = tanf(MatrixMath.radians(fromDegrees: 60))
            let normal = simd_normalize(SIMD3<Float>(-rise, 0, 1))
            return TerrainGroundSample(height: (position.x - 450) * rise, normal: normal)
        }
        var camera = CapsuleCollisionTests.camera(feet: SIMD3(-150, 0, 100))
        var controller = WalkController(cameraPosition: camera.position)
        Self.walk(
            &controller, camera: &camera, forward: 1, steps: 120, ground: bank,
            query: DynamicBodyScene.candidateQuery([dock])
        )

        #expect(controller.feetPosition.x > 0)
        #expect(abs(controller.feetPosition.z - 100) < 0.5)
        #expect(controller.isGrounded)
    }

    @Test
    func aStairOfSeveralTreadsIsClimbedTreadByTread() {
        // Three treads of 18 units, each 40 deep, as on the Riverwood walkway stairs.
        let floor = DynamicBodyScene.floor(extent: 400)
        let treads = (0 ..< 3).map { index in
            let top = Float(index + 1) * 18
            let start = 40 + Float(index) * 40
            return DynamicBodyScene.box(
                center: SIMD3((start + 400) / 2, 0, top / 2),
                half: SIMD3((400 - start) / 2, 100, top / 2)
            )
        }
        var camera = CapsuleCollisionTests.camera(feet: .zero)
        var controller = WalkController(cameraPosition: camera.position)
        Self.walk(
            &controller, camera: &camera, forward: 1, steps: 120,
            query: DynamicBodyScene.candidateQuery([floor] + treads)
        )

        #expect(abs(controller.feetPosition.z - 54) < 0.5)
        #expect(controller.isGrounded)
    }

    @Test
    func aDropWithinTheGroundSearchKeepsTheWalkerOnTheGround() {
        let ledge = DynamicBodyScene.box(center: SIMD3(-100, 0, 20), half: SIMD3(100, 100, 20))
        let floor = DynamicBodyScene.floor(extent: 400)
        var camera = CapsuleCollisionTests.camera(feet: SIMD3(-60, 0, 40))
        var controller = WalkController(cameraPosition: camera.position)
        var leftTheGround = false
        for _ in 0 ..< 60 {
            Self.walk(
                &controller, camera: &camera, forward: 1, steps: 1,
                query: DynamicBodyScene.candidateQuery([ledge, floor])
            )
            leftTheGround = leftTheGround || !controller.isGrounded
        }

        #expect(!leftTheGround)
        #expect(controller.feetPosition.x > 40)
        #expect(abs(controller.feetPosition.z) < 0.5)
        #expect(controller.takeLanding() == nil)
    }

    @Test
    func aFallPullsHarderThanTheRiseOfAJump() {
        var camera = CapsuleCollisionTests.camera(feet: SIMD3(0, 0, 5000))
        var controller = WalkController(cameraPosition: camera.position)
        controller.knock(SIMD3(0, 0, 700))
        Self.walk(&controller, camera: &camera, forward: 0, steps: 1)
        let rising = 700 - controller.verticalVelocity
        // Half a second after the apex the speed has grown at 1.35 times gravity.
        while controller.verticalVelocity > 0 {
            Self.walk(&controller, camera: &camera, forward: 0, steps: 1)
        }
        let atApex = controller.verticalVelocity
        Self.walk(&controller, camera: &camera, forward: 0, steps: 60)
        let falling = atApex - controller.verticalVelocity

        #expect(abs(rising - PhysicsStep.gravity * WalkController.fixedTimeStep) < 0.01)
        #expect(abs(falling - 1.35 * PhysicsStep.gravity * 0.5) < 1)
    }
}

extension WalkControllerSlopeTests {
    static func height(at x: Float, degrees: Float) -> Float {
        max(x, 0) * tanf(MatrixMath.radians(fromDegrees: degrees))
    }

    /// Flat ground west of x = 0, then a rise of `degrees` to the east.
    static func terrainSlope(degrees: Float) -> WalkController.GroundSampler {
        let rise = tanf(MatrixMath.radians(fromDegrees: degrees))
        let normal = simd_normalize(SIMD3<Float>(-rise, 0, 1))
        return { position in
            position.x < 0
                ? TerrainGroundSample(height: 0, normal: SIMD3(0, 0, 1))
                : TerrainGroundSample(height: position.x * rise, normal: normal)
        }
    }

    /// The same shape as `terrainSlope`, as collision meshes.
    static func meshSlope(degrees: Float) -> [StaticCollisionShape] {
        let top = height(at: 600, degrees: degrees)
        return [
            DynamicBodyScene.quad(
                SIMD3(-400, -200, 0), SIMD3(0, -200, 0), SIMD3(0, 200, 0), SIMD3(-400, 200, 0)
            ),
            DynamicBodyScene.quad(
                SIMD3(0, -200, 0), SIMD3(600, -200, top), SIMD3(600, 200, top), SIMD3(0, 200, 0)
            )
        ]
    }

    static func walk(
        _ controller: inout WalkController,
        camera: inout FreeFlyCamera,
        forward: Float,
        steps: Int,
        ground: WalkController.GroundSampler = { _ in nil },
        query: WalkController.CollisionQuery = { _ in [] }
    ) {
        for _ in 0 ..< steps {
            controller.update(
                camera: &camera,
                input: CameraInput(
                    moveForward: forward,
                    boost: true,
                    dt: WalkController.fixedTimeStep
                ),
                sampleGround: ground,
                collisionQuery: query
            )
        }
    }
}
