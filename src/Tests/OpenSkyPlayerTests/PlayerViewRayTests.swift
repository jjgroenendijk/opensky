// The crosshair's pick ray in each camera mode, against collision built in code.

@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
@testable import OpenSkyPlayer
@testable import OpenSkyRenderCore
@testable import OpenSkyWorldInterface
import simd
import Testing

struct PlayerViewRayTests {
    private static let feet = SIMD3<Float>(1000, 2000, 50)
    private static let door = FormID(0x0001_3A6F)
    private static let bucket = FormID(0x0001_3A70)

    private static func box(
        _ reference: FormID, at center: SIMD3<Float>, half: SIMD3<Float>
    ) -> StaticCollisionShape {
        StaticCollisionShape(
            reference: reference,
            transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: half),
            bounds: ModelBounds(min: center - half, max: center + half)
        )
    }

    /// A camera as third person places it: behind the player at the orbit distance.
    private static func thirdPersonCamera(pitch: Float = 0) -> FreeFlyCamera {
        var camera = FreeFlyCamera(position: .zero, yaw: 0, pitch: pitch)
        camera.position = ThirdPersonCamera.pivot(feetPosition: feet)
            + ThirdPersonCamera.idealOffset(yaw: 0, pitch: pitch)
        return camera
    }

    @Test
    func thirdPersonPicksADoorInFrontOfThePlayer() throws {
        let camera = Self.thirdPersonCamera()
        let doorCenter = Self.feet + SIMD3(80, -ThirdPersonCamera.shoulderOffset, 64)
        let shapes = [Self.box(Self.door, at: doorCenter, half: SIMD3(4, 48, 64))]
        let ray = try #require(PlayerViewRay.make(
            mode: .thirdPerson, camera: camera, feetPosition: Self.feet
        ))
        let hit = try #require(InteractionRaycaster.nearestHit(ray: ray, shapes: shapes))
        #expect(hit.reference == Self.door)
        #expect(abs(hit.distance - 76) < 0.01)
        // A ray from the camera itself runs out of reach before the door.
        let fromCamera = try #require(InteractionRay(
            origin: camera.position, direction: camera.forward
        ))
        #expect(InteractionRaycaster.nearestHit(ray: fromCamera, shapes: shapes) == nil)
    }

    @Test
    func thirdPersonPicksAnItemTheViewLooksDownOn() throws {
        let pitch = -Float.pi / 4
        let camera = Self.thirdPersonCamera(pitch: pitch)
        let ray = try #require(PlayerViewRay.make(
            mode: .thirdPerson, camera: camera, feetPosition: Self.feet
        ))
        let bucketCenter = ray.origin + camera.forward * 100
        let shapes = [Self.box(Self.bucket, at: bucketCenter, half: SIMD3(repeating: 8))]
        let hit = try #require(InteractionRaycaster.nearestHit(ray: ray, shapes: shapes))
        #expect(hit.reference == Self.bucket)
    }

    @Test
    func firstPersonStartsAtTheEyeAndFlyPicksNothing() throws {
        let camera = FreeFlyCamera(position: SIMD3(1, 2, 3), yaw: 0.5, pitch: 0.1)
        let ray = try #require(PlayerViewRay.make(
            mode: .walk, camera: camera, feetPosition: .zero, reach: 800
        ))
        #expect(ray.origin == camera.position)
        #expect(ray.maximumDistance == 800)
        #expect(simd_distance(ray.direction, camera.forward) < 1e-5)
        #expect(PlayerViewRay.make(mode: .fly, camera: camera, feetPosition: .zero) == nil)
    }
}
