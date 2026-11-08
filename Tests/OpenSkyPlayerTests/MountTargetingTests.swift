// What a dragon rider can lock: inside the cone and the range, with its side.

@testable import OpenSkyPlayer
import Testing

struct MountTargetingTests {
    private static let north = SIMD3<Float>(0, 1, 0)

    @Test
    func anActorAheadIsInView() throws {
        let view = try #require(MountTargeting.view(
            of: SIMD3(0, 1000, 0), forward: Self.north, within: MountTargeting.lockCone
        ))
        #expect(abs(view.angle) < 0.001 && abs(view.bearing) < 0.001)
    }

    @Test
    func theBearingIsPositiveToTheLeft() throws {
        let view = try #require(MountTargeting.view(
            of: SIMD3(-500, 1000, 0), forward: Self.north, within: MountTargeting.switchCone
        ))
        #expect(view.bearing > 0)
    }

    @Test
    func outsideTheConeOrRangeIsNotInView() {
        let cone = MountTargeting.lockCone
        #expect(MountTargeting
            .view(of: SIMD3(1000, 1000, 0), forward: Self.north, within: cone) == nil)
        #expect(MountTargeting
            .view(of: SIMD3(0, 9000, 0), forward: Self.north, within: cone) == nil)
        #expect(MountTargeting.view(of: SIMD3(0, 0.5, 0), forward: Self.north, within: cone) == nil)
    }
}
