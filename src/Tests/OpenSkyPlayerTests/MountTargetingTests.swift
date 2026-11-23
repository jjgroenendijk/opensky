// What a dragon rider can lock or switch to: the range, the cone, and the side.

@testable import OpenSkyPlayer
import Testing

struct MountTargetingTests {
    private static let north = SIMD3<Float>(0, 1, 0)

    @Test
    func anActorAheadIsInView() throws {
        let view = try #require(MountTargeting.view(
            of: SIMD3(0, 1000, 0), forward: Self.north, within: 0.25
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
        let cone: Float = 0.25
        #expect(MountTargeting
            .view(of: SIMD3(1000, 1000, 0), forward: Self.north, within: cone) == nil)
        #expect(MountTargeting
            .view(of: SIMD3(0, 9000, 0), forward: Self.north, within: cone) == nil)
        #expect(MountTargeting.view(of: SIMD3(0, 0.5, 0), forward: Self.north, within: cone) == nil)
    }

    @Test
    func theLockTakesActorsInRangeOnTheGroundPlaneNearestFirst() {
        let actors: [(key: Int, feet: SIMD3<Float>)] = [
            (1, SIMD3(7000, 0, 0)), (2, SIMD3(0, 100, 9000)), (3, SIMD3(0, 7600, 0)),
            (4, SIMD3(-3000, 0, 0))
        ]
        #expect(MountTargeting.lockOrder(of: actors, around: .zero) == [2, 4, 1])
        #expect(MountTargeting.lockOrder(of: actors, around: SIMD3(0, 7600, 0)) == [3, 2])
    }
}
