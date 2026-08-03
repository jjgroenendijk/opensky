// Third-person camera framing, mode cycling, and collision zoom (issue #189).
// Synthetic geometry only — no install, no device.

@testable import opensky
import simd
import Testing

struct ThirdPersonCameraTests {
    // MARK: - Mode cycling

    /// One key press and one popup selection walk the same three modes in the
    /// same order, so neither can reach a mode the other cannot.
    @Test
    func cyclingVisitsEveryModeAndReturnsToFly() {
        var mode = CameraMovementMode.fly
        var visited: [CameraMovementMode] = []
        for _ in 0 ..< CameraMovementMode.allCases.count {
            mode = mode.next
            visited.append(mode)
        }
        #expect(visited == [.walk, .thirdPerson, .fly])
        #expect(Set(visited) == Set(CameraMovementMode.allCases))
    }

    @Test
    func onlyFlyIsNotPlayerControlled() {
        #expect(!CameraMovementMode.fly.isPlayerControlled)
        #expect(CameraMovementMode.walk.isPlayerControlled)
        #expect(CameraMovementMode.thirdPerson.isPlayerControlled)
    }

    // MARK: - Framing

    /// The orbit distance is the framing derivation, not a stored constant:
    /// recomputing it from the capsule and the fov has to give the same answer,
    /// which is what makes changing either of those inputs move the camera
    /// instead of silently disagreeing with the documentation.
    @Test
    func orbitDistanceFramesTheCapsuleAtTheStatedFill() {
        let halfHeight = PlayerCapsule.standard.height / 2
        let expected = (halfHeight / ThirdPersonCamera.framingFillFraction)
            / tanf(ThirdPersonCamera.fovYRadians / 2)
        #expect(abs(ThirdPersonCamera.orbitDistance - expected) < 0.001)
        // The subject really does fill the stated fraction at that distance.
        let halfViewHeight = ThirdPersonCamera.orbitDistance
            * tanf(ThirdPersonCamera.fovYRadians / 2)
        #expect(
            abs(halfHeight / halfViewHeight - ThirdPersonCamera.framingFillFraction) < 0.001
        )
    }

    /// The fov the framing is derived from must be the fov the renderer
    /// projects with, or the body is framed for a camera nobody looks through.
    @Test
    func framingFovMatchesTheProjectionFov() {
        #expect(
            abs(ThirdPersonCamera.fovYRadians - MatrixMath.radians(fromDegrees: 65)) < 1e-6
        )
    }

    /// The pivot is the first-person eye, so switching modes does not change
    /// what is at the centre of the screen.
    @Test
    func pivotIsTheFirstPersonEye() {
        let feet = SIMD3<Float>(100, -50, 20)
        let controller = WalkController(
            cameraPosition: feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight)
        )
        #expect(ThirdPersonCamera.pivot(feetPosition: feet) == controller.cameraPosition)
    }

    /// Looking east along +X, the eye sits behind the pivot on -X and one
    /// shoulder offset to the camera's right, which in this basis is -Y.
    @Test
    func idealOffsetSitsBehindAndOffTheShoulder() {
        let offset = ThirdPersonCamera.idealOffset(yaw: 0, pitch: 0)
        #expect(abs(offset.x + ThirdPersonCamera.orbitDistance) < 0.001)
        #expect(abs(offset.y + ThirdPersonCamera.shoulderOffset) < 0.001)
        #expect(abs(offset.z) < 0.001)
    }

    /// Looking up raises the eye and shortens its horizontal reach, because the
    /// orbit is a sphere rather than a ring.
    @Test
    func pitchOrbitsTheEyeVertically() {
        let level = ThirdPersonCamera.idealOffset(yaw: 0, pitch: 0)
        let raised = ThirdPersonCamera.idealOffset(
            yaw: 0, pitch: MatrixMath.radians(fromDegrees: 30)
        )
        #expect(raised.z < level.z)
        #expect(raised.x > level.x)
        // Same orbit radius, whichever way it is aimed.
        #expect(abs(simd_length(raised) - simd_length(level)) < 0.001)
    }

    // MARK: - Collision zoom

    @Test
    func openSpaceLeavesTheCameraAtTheOrbitDistance() {
        var camera = ThirdPersonCamera()
        let eye = camera.resolve(
            feetPosition: .zero, yaw: 0, pitch: 0, collisionQuery: { _ in [] }
        )
        let pivot = ThirdPersonCamera.pivot(feetPosition: .zero)
        #expect(abs(simd_length(eye - pivot) - camera.resolvedDistance) < 0.001)
        #expect(
            abs(camera.resolvedDistance - simd_length(
                ThirdPersonCamera.idealOffset(yaw: 0, pitch: 0)
            )) < 0.001
        )
        #expect(!camera.isCollisionLimited)
    }

    /// A wall close behind the player pulls the camera in rather than letting it
    /// pass through: the resolved eye stays on the near side of the wall.
    @Test
    func aWallBehindThePlayerPullsTheCameraIn() {
        var camera = ThirdPersonCamera()
        let wallX: Float = -60
        let wall = Self.quad(
            SIMD3(wallX, -400, -400), SIMD3(wallX, 400, -400),
            SIMD3(wallX, 400, 400), SIMD3(wallX, -400, 400)
        )
        let eye = camera.resolve(
            feetPosition: .zero,
            yaw: 0,
            pitch: 0,
            collisionQuery: Self.query([wall])
        )
        #expect(camera.isCollisionLimited)
        #expect(camera.resolvedDistance < ThirdPersonCamera.orbitDistance)
        #expect(eye.x > wallX)
        // Still on the orbit line, just shorter.
        let pivot = ThirdPersonCamera.pivot(feetPosition: .zero)
        let direction = simd_normalize(ThirdPersonCamera.idealOffset(yaw: 0, pitch: 0))
        #expect(simd_length(eye - (pivot + direction * camera.resolvedDistance)) < 0.001)
    }

    /// Standing with a wall pressed against the player's back never collapses
    /// the eye into the head: the pull-in stops at `minimumDistance`.
    @Test
    func theZoomNeverCollapsesPastTheMinimum() {
        var camera = ThirdPersonCamera()
        let wall = Self.quad(
            SIMD3(-2, -400, -400), SIMD3(-2, 400, -400),
            SIMD3(-2, 400, 400), SIMD3(-2, -400, 400)
        )
        _ = camera.resolve(
            feetPosition: .zero,
            yaw: 0,
            pitch: 0,
            collisionQuery: Self.query([wall])
        )
        #expect(camera.resolvedDistance >= ThirdPersonCamera.minimumDistance)
    }

    /// A teleport must not carry the zoom state of the place the player left.
    @Test
    func resetRestoresTheOrbitDistance() {
        var camera = ThirdPersonCamera()
        let wall = Self.quad(
            SIMD3(-60, -400, -400), SIMD3(-60, 400, -400),
            SIMD3(-60, 400, 400), SIMD3(-60, -400, 400)
        )
        _ = camera.resolve(
            feetPosition: .zero, yaw: 0, pitch: 0, collisionQuery: Self.query([wall])
        )
        camera.reset()
        #expect(camera.resolvedDistance == ThirdPersonCamera.orbitDistance)
        #expect(!camera.isCollisionLimited)
    }

    // MARK: - Synthetic geometry

    private static func query(
        _ shapes: [StaticCollisionShape]
    ) -> WalkController.CollisionQuery {
        StaticCollisionSet(
            location: nil,
            shapes: shapes,
            stats: StaticCollisionStats()
        ).candidates
    }

    private static func quad(
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
}
