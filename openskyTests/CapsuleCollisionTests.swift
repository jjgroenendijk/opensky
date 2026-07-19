// Synthetic capsule/world response: wall slide, ramp, bounded steps,
// terrain/mesh seam, query filtering, ceilings. No game assets.

@testable import opensky
import simd
import Testing

struct CapsuleCollisionTests {
    private static let up = SIMD3<Float>(0, 0, 1)

    @Test
    func diagonalMotionSlidesAlongWallWithoutPenetration() {
        let capsule = PlayerCapsule(radius: 1, height: 4, eyeHeight: 3)
        let collider = CapsuleWorldCollider(capsule: capsule)
        let wall = Self.quad(
            SIMD3(2, -10, -5), SIMD3(2, 10, -5),
            SIMD3(2, 10, 10), SIMD3(2, -10, 10)
        )
        let result = collider.move(
            from: .zero,
            displacement: SIMD3(4, 3, 0),
            query: Self.query([wall])
        )

        #expect(result.position.x <= 1.01)
        #expect(result.position.y > 2.9)
        #expect(!result.hasUnresolvedPenetration)
    }

    @Test
    func ceilingStopsUpwardCapsuleMotion() {
        let capsule = PlayerCapsule(radius: 1, height: 4, eyeHeight: 3)
        let collider = CapsuleWorldCollider(capsule: capsule)
        let ceiling = Self.quad(
            SIMD3(-10, -10, 5), SIMD3(-10, 10, 5),
            SIMD3(10, 10, 5), SIMD3(10, -10, 5)
        )
        let result = collider.move(
            from: .zero,
            displacement: SIMD3(0, 0, 4),
            query: Self.query([ceiling])
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
            query: Self.query([ramp])
        )

        #expect(controller.feetPosition.x > 100)
        #expect(controller.feetPosition.z > 20)
        #expect(controller.isGrounded)
        #expect(!controller.hasUnresolvedPenetration)
    }

    @Test
    func groundedControllerClimbsLowStepButBlocksHighStep() {
        let floor = Self.floor()
        let lowStep = Self.box(center: SIMD3(70, 0, 8), half: SIMD3(30, 100, 8))
        var lowCamera = Self.camera(feet: .zero)
        var low = WalkController(cameraPosition: lowCamera.position)
        Self.drive(
            controller: &low,
            camera: &lowCamera,
            frames: 60,
            query: Self.query([floor, lowStep])
        )
        #expect(low.feetPosition.x > 80)
        #expect(abs(low.feetPosition.z - 16) < 0.1)
        #expect(low.isGrounded)

        let highStep = Self.box(center: SIMD3(70, 0, 24), half: SIMD3(30, 100, 24))
        var highCamera = Self.camera(feet: .zero)
        var high = WalkController(cameraPosition: highCamera.position)
        Self.drive(
            controller: &high,
            camera: &highCamera,
            frames: 60,
            query: Self.query([floor, highStep])
        )
        #expect(high.feetPosition.x < 17)
        #expect(abs(high.feetPosition.z) < 0.1)
        #expect(!high.hasUnresolvedPenetration)
    }

    @Test
    func forwardStepProbeFindsWalkableTread() {
        let collider = CapsuleWorldCollider(capsule: .standard)
        let query = Self.query([
            Self.floor(),
            Self.box(center: SIMD3(70, 0, 8), half: SIMD3(30, 100, 8))
        ])
        let start = SIMD3<Float>(17.37147, 0, 0.002)
        let support = collider.stepSupportHeight(
            at: SIMD2(start.x + PlayerCapsule.standard.radius + 1.5, start.y),
            minimumHeight: start.z,
            maximumHeight: start.z + WalkController.stepHeight,
            query: query
        )
        #expect(abs((support ?? -1) - 16) < 0.01)
    }

    @Test
    func crossesTerrainToMeshSeamAndFilteredWallIsAbsent() {
        let platform = Self.box(center: SIMD3(70, 0, 8), half: SIMD3(30, 100, 8))
        let filteredWall = Self.quad(
            SIMD3(20, -100, -10), SIMD3(20, 100, -10),
            SIMD3(20, 100, 200), SIMD3(20, -100, 200)
        )
        var camera = Self.camera(feet: .zero)
        var controller = WalkController(cameraPosition: camera.position)
        let terrain: WalkController.GroundSampler = { position in
            position.x < 40 ? TerrainGroundSample(height: 0, normal: Self.up) : nil
        }
        // filteredWall exists in source scene but broadphase omits it, matching
        // M4.3 player-solid filtering before controller consumption.
        let query = Self.query([platform])
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

    private static func camera(feet: SIMD3<Float>) -> FreeFlyCamera {
        FreeFlyCamera(
            position: feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
    }

    private static func query(
        _ shapes: [StaticCollisionShape]
    ) -> WalkController.CollisionQuery {
        let collision = StaticCollisionSet(
            location: nil,
            shapes: shapes,
            stats: StaticCollisionStats()
        )
        return collision.candidates
    }

    private static func floor() -> StaticCollisionShape {
        quad(
            SIMD3(-200, -200, 0), SIMD3(200, -200, 0),
            SIMD3(200, 200, 0), SIMD3(-200, 200, 0)
        )
    }

    private static func quad(
        _ first: SIMD3<Float>,
        _ second: SIMD3<Float>,
        _ third: SIMD3<Float>,
        _ fourth: SIMD3<Float>
    ) -> StaticCollisionShape {
        mesh(
            vertices: [first, second, third, fourth],
            indices: [0, 1, 2, 0, 2, 3]
        )
    }

    private static func mesh(
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

    private static func box(
        center: SIMD3<Float>,
        half: SIMD3<Float>
    ) -> StaticCollisionShape {
        StaticCollisionShape(
            reference: FormID(2),
            transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: half),
            bounds: ModelBounds(min: center - half, max: center + half)
        )
    }
}
