@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
import simd
import Testing

struct ShadowReachTests {
    private let reach = ShadowReach(centre: SIMD3(0, 0, 0), radius: 100)

    @Test func aBoxAroundTheLightIsReached() {
        #expect(reach.touches(ModelBounds(min: SIMD3(-10, -10, -10), max: SIMD3(10, 10, 10))))
    }

    @Test func aBoxBesideTheSphereIsReached() {
        #expect(reach.touches(ModelBounds(min: SIMD3(99, -5, -5), max: SIMD3(200, 5, 5))))
    }

    @Test func aBoxPastTheRadiusIsNotReached() {
        #expect(!reach.touches(ModelBounds(min: SIMD3(101, -5, -5), max: SIMD3(200, 5, 5))))
    }

    /// The box corner is nearer on each axis than the radius, but not along the diagonal.
    @Test func aBoxOffTheDiagonalIsNotReached() {
        #expect(!reach.touches(ModelBounds(min: SIMD3(80, 80, 80), max: SIMD3(90, 90, 90))))
    }
}
