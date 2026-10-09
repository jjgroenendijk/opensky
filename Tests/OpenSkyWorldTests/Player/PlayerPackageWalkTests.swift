// The package walk faces the player to the target and stops near it.

@testable import OpenSkyWorld
import simd
import Testing

struct PlayerPackageWalkTests {
    @Test func theWalkFacesTheTargetUntilItIsNear() throws {
        let yaw = try #require(PlayerPackageWalk.steeringYaw(
            feet: .zero,
            target: SIMD3(0, 100, 50)
        ))
        #expect(abs(yaw - .pi / 2) < 0.0001)
        #expect(PlayerPackageWalk.steeringYaw(feet: .zero, target: SIMD3(5, 5, 300)) == nil)
    }

    @Test func reachedWaypointsDropFromThePath() {
        let path: [SIMD3<Float>] = [SIMD3(10, 0, 0), SIMD3(30, 0, 0), SIMD3(200, 0, 0)]
        #expect(PlayerPackageWalk.remainingPath(path, feet: .zero) == [SIMD3(200, 0, 0)])
        #expect(PlayerPackageWalk.remainingPath([SIMD3(200, 0, 0)], feet: SIMD3(200, 10, 0))
            .isEmpty)
    }
}
