// Focus shadows pick the nearest actors and fit a view around each one.

@testable import OpenSkyFormatsCore
@testable import OpenSkyRenderCore
import simd
import Testing

struct FocusShadowMathTests {
    static func target(_ owner: UInt32, at x: Float) -> FocusShadowTarget {
        FocusShadowTarget(
            owner: owner,
            bounds: ModelBounds(min: SIMD3(x - 32, -32, 0), max: SIMD3(x + 32, 32, 128))
        )
    }

    @Test
    func theNearestActorsInRangeComeFirst() {
        let targets = [Self.target(1, at: 900), Self.target(2, at: 100), Self.target(3, at: 5000)]
        let picked = FocusShadowMath.pick(targets, viewer: .zero, count: 4)
        #expect(picked.map(\.owner) == [2, 1])
        #expect(FocusShadowMath.pick(targets, viewer: .zero, count: 1).map(\.owner) == [2])
        #expect(FocusShadowMath.pick(targets, viewer: .zero, count: 0).isEmpty)
    }

    @Test
    func theActorSitsInsideItsView() {
        let bounds = Self.target(1, at: 300).bounds
        let matrix = FocusShadowMath.viewProjection(
            bounds: bounds, sunDirection: simd_normalize(SIMD3(0.3, 0.2, -1))
        )
        for corner in [bounds.min, bounds.max, (bounds.min + bounds.max) * 0.5] {
            let clip = matrix * SIMD4(corner, 1)
            #expect(abs(clip.x) <= 1.001 && abs(clip.y) <= 1.001)
            #expect(clip.z >= 0 && clip.z <= 1)
        }
    }
}
