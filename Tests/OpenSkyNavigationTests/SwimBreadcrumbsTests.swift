// A follower swims after the player along the player's own swim path.

@testable import OpenSkyNavigation
import simd
import Testing

struct SwimBreadcrumbsTests {
    @Test func onlyASwimDropsPointsAndOnlyEveryStretch() {
        var crumbs = SwimBreadcrumbs()
        crumbs.record(SIMD3(0, 0, 0), isSwimming: false)
        crumbs.record(SIMD3(0, 0, 0), isSwimming: true)
        crumbs.record(SIMD3(50, 0, 0), isSwimming: true)
        crumbs.record(SIMD3(200, 0, 0), isSwimming: true)
        #expect(crumbs.points == [SIMD3(0, 0, 0), SIMD3(200, 0, 0)])
    }

    @Test func theTrailStartsAtTheNearestPointAndEndsAtTheTarget() {
        var crumbs = SwimBreadcrumbs()
        for step in 0 ..< 5 {
            crumbs.record(SIMD3(Float(step) * 200, 0, 0), isSwimming: true)
        }
        let trail = crumbs.trail(from: SIMD3(390, 50, 0), to: SIMD3(900, 0, 0))
        #expect(trail?.first == SIMD3(400, 0, 0))
        #expect(trail?.last == SIMD3(900, 0, 0))
        #expect(crumbs.trail(from: .zero, to: SIMD3(5000, 0, 0)) == nil, "it leads elsewhere")
        #expect(crumbs.trail(from: SIMD3(0, 5000, 0), to: SIMD3(900, 0, 0)) == nil, "too far")
    }
}
