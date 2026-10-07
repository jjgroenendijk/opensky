// Synthetic capsule/world response: wall slide, ramp, bounded steps,
// terrain/mesh seam, query filtering, ceilings. No game assets.

import EngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

struct CapsuleCollisionTests {
    private static let up = SIMD3<Float>(0, 0, 1)

    @Test
    func diagonalMotionSlidesAlongWallWithoutPenetration() {
        let capsule = PlayerCapsule(radius: 1, height: 4, eyeHeight: 3)
        let collider = CapsuleWorldCollider(capsule: capsule)
        let wall = DynamicBodyScene.quad(
            SIMD3(2, -10, -5), SIMD3(2, 10, -5),
            SIMD3(2, 10, 10), SIMD3(2, -10, 10)
        )
        let result = collider.move(
            from: .zero,
            displacement: SIMD3(4, 3, 0),
            query: DynamicBodyScene.candidateQuery([wall])
        )

        #expect(result.position.x <= 1.01)
        #expect(result.position.y > 2.9)
        #expect(!result.hasUnresolvedPenetration)
    }

    @Test
    func ceilingStopsUpwardCapsuleMotion() {
        let capsule = PlayerCapsule(radius: 1, height: 4, eyeHeight: 3)
        let collider = CapsuleWorldCollider(capsule: capsule)
        let ceiling = DynamicBodyScene.quad(
            SIMD3(-10, -10, 5), SIMD3(-10, 10, 5),
            SIMD3(10, 10, 5), SIMD3(10, -10, 5)
        )
        let result = collider.move(
            from: .zero,
            displacement: SIMD3(0, 0, 4),
            query: DynamicBodyScene.candidateQuery([ceiling])
        )

        #expect(result.position.z <= 1.01)
        #expect(result.contacts.contains { $0.normal.z < -0.9 })
        #expect(!result.hasUnresolvedPenetration)
    }

    @Test
    func convexSphereAndCapsulePrimitivesBlockMotion() {
        let half = SIMD3<Float>(1, 10, 10)
        let cubeVertices = CapsuleWorldCollider.boxVertices(half)
        let obstacles = [
            Self.shape(
                geometry: .convexVertices(
                    vertices: cubeVertices,
                    hullIndices: CapsuleWorldCollider.boxIndices
                ),
                center: SIMD3(3, 0, 2),
                localBounds: ModelBounds(min: -half, max: half)
            ),
            Self.shape(
                geometry: .sphere(radius: 1),
                center: SIMD3(3, 0, 2),
                localBounds: ModelBounds(min: -half, max: half)
            ),
            Self.shape(
                geometry: .capsule(
                    first: SIMD3(0, 0, -1),
                    second: SIMD3(0, 0, 1),
                    radius: 1
                ),
                center: SIMD3(3, 0, 2),
                localBounds: ModelBounds(
                    min: SIMD3(-1, -1, -2),
                    max: SIMD3(1, 1, 2)
                )
            )
        ]
        let collider = CapsuleWorldCollider(
            capsule: PlayerCapsule(radius: 1, height: 4, eyeHeight: 3)
        )

        for (index, obstacle) in obstacles.enumerated() {
            let result = collider.move(
                from: .zero,
                displacement: SIMD3(6, 0, 0),
                query: { _ in [obstacle] }
            )
            #expect(result.position.x <= 1.01, "primitive index \(index)")
            #expect(!result.hasUnresolvedPenetration, "primitive index \(index)")
        }
    }

    @Test
    func walkControllerClimbsWalkableRamp() {
        let ramp = Self.mesh(
            vertices: [
                SIMD3(-50, -100, 0), SIMD3(200, -100, 50),
                SIMD3(200, 100, 50), SIMD3(-50, 100, 0)
            ],
            indices: [0, 1, 2, 0, 2, 3]
        )
        var camera = Self.camera(feet: SIMD3(-25, 0, 5))
        var controller = WalkController(cameraPosition: camera.position)
        Self.drive(
            controller: &controller,
            camera: &camera,
            frames: 100,
            query: DynamicBodyScene.candidateQuery([ramp])
        )

        #expect(controller.feetPosition.x > 100)
        #expect(controller.feetPosition.z > 20)
        #expect(controller.isGrounded)
        #expect(!controller.hasUnresolvedPenetration)
    }

    @Test
    func groundedControllerClimbsLowStepButBlocksHighStep() {
        let floor = DynamicBodyScene.floor(extent: 200)
        let lowStep = DynamicBodyScene.box(center: SIMD3(70, 0, 8), half: SIMD3(30, 100, 8))
        var lowCamera = Self.camera(feet: .zero)
        var low = WalkController(cameraPosition: lowCamera.position)
        Self.drive(
            controller: &low,
            camera: &lowCamera,
            frames: 60,
            query: DynamicBodyScene.candidateQuery([floor, lowStep])
        )
        #expect(low.feetPosition.x > 80)
        #expect(abs(low.feetPosition.z - 16) < 0.1)
        #expect(low.isGrounded)

        let highStep = DynamicBodyScene.box(center: SIMD3(70, 0, 24), half: SIMD3(30, 100, 24))
        var highCamera = Self.camera(feet: .zero)
        var high = WalkController(cameraPosition: highCamera.position)
        Self.drive(
            controller: &high,
            camera: &highCamera,
            frames: 60,
            query: DynamicBodyScene.candidateQuery([floor, highStep])
        )
        #expect(high.feetPosition.x < 17)
        #expect(abs(high.feetPosition.z) < 0.1)
        #expect(!high.hasUnresolvedPenetration)
    }

    @Test
    func forwardStepProbeFindsWalkableTread() {
        let collider = CapsuleWorldCollider(capsule: .standard)
        let query = DynamicBodyScene.candidateQuery([
            DynamicBodyScene.floor(extent: 200),
            DynamicBodyScene.box(center: SIMD3(70, 0, 8), half: SIMD3(30, 100, 8))
        ])
        let start = SIMD3<Float>(17.37147, 0, 0.002)
        let support = collider.stepSupport(
            at: SIMD2(start.x + PlayerCapsule.standard.radius + 1.5, start.y),
            minimumHeight: start.z,
            maximumHeight: start.z + PlayerMovementConfiguration.synthetic.stepHeight.value,
            query: query
        )
        #expect(abs((support?.height ?? -1) - 16) < 0.01)
    }

    @Test
    func crossesTerrainToMeshSeamAndFilteredWallIsAbsent() {
        let platform = DynamicBodyScene.box(center: SIMD3(70, 0, 8), half: SIMD3(30, 100, 8))
        let filteredWall = DynamicBodyScene.quad(
            SIMD3(20, -100, -10), SIMD3(20, 100, -10),
            SIMD3(20, 100, 200), SIMD3(20, -100, 200)
        )
        var camera = Self.camera(feet: .zero)
        var controller = WalkController(cameraPosition: camera.position)
        let terrain: WalkController.GroundSampler = { position in
            position.x < 40 ? TerrainGroundSample(height: 0, normal: Self.up) : nil
        }
        // filteredWall is in the scene, but the broadphase omits it, as the
        // player-solid filter does.
        let query = DynamicBodyScene.candidateQuery([platform])
        #expect(filteredWall.bounds.min.x == 20)
        for _ in 0 ..< 60 {
            controller.update(
                camera: &camera,
                input: CameraInput(moveForward: 1, dt: WalkController.fixedTimeStep),
                sampleGround: terrain,
                collisionQuery: query
            )
        }

        #expect(controller.feetPosition.x > 80)
        #expect(abs(controller.feetPosition.z - 16) < 0.1)
        #expect(controller.isGrounded)
    }

    private static func drive(
        controller: inout WalkController,
        camera: inout FreeFlyCamera,
        frames: Int,
        query: @escaping WalkController.CollisionQuery
    ) {
        for _ in 0 ..< frames {
            controller.update(
                camera: &camera,
                input: CameraInput(moveForward: 1, dt: WalkController.fixedTimeStep),
                sampleGround: { _ in nil },
                collisionQuery: query
            )
        }
    }

    static func camera(feet: SIMD3<Float>) -> FreeFlyCamera {
        FreeFlyCamera(
            position: feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
    }

    static func mesh(
        vertices: [SIMD3<Float>],
        indices: [UInt32]
    ) -> StaticCollisionShape {
        StaticCollisionShape(
            reference: FormID(1),
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(vertices: vertices, indices: indices),
            bounds: ModelBounds.containing(vertices) ?? ModelBounds(min: .zero, max: .zero)
        )
    }
}

extension CapsuleCollisionTests {
    /// Gravity pushes straight down, so a standing player must not creep downhill
    /// on a walkable mesh slope.
    @Test
    func standingOnAWalkableSlopeDoesNotCreep() {
        let ramp = Self.mesh(
            vertices: [
                SIMD3(-200, -100, -40), SIMD3(200, -100, 40),
                SIMD3(200, 100, 40), SIMD3(-200, 100, -40)
            ],
            indices: [0, 1, 2, 0, 2, 3]
        )
        var camera = Self.camera(feet: SIMD3(0, 0, 2))
        var controller = WalkController(cameraPosition: camera.position)
        for _ in 0 ..< 300 {
            controller.update(
                camera: &camera,
                input: CameraInput(dt: WalkController.fixedTimeStep),
                sampleGround: { _ in nil },
                collisionQuery: DynamicBodyScene.candidateQuery([ramp])
            )
        }

        #expect(controller.isGrounded)
        #expect(abs(controller.feetPosition.x) < 0.05)
        #expect(abs(controller.feetPosition.y) < 0.05)
    }
}
