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
        let targets = [Self.target(1, at: 300), Self.target(2, at: 100), Self.target(3, at: 900)]
        let picked = FocusShadowMath.pick(targets, viewer: .zero, count: 4)
        #expect(picked.map(\.target.owner) == [2, 1])
        #expect(FocusShadowMath.pick(targets, viewer: .zero, count: 1).map(\.target.owner) == [2])
        #expect(FocusShadowMath.pick(targets, viewer: .zero, count: 0).isEmpty)
    }

    @Test
    func strengthFadesWithTheSquaredDistance() {
        #expect(FocusShadowMath.strength(distance: 200) == 1)
        #expect(FocusShadowMath.strength(distance: 225) == 1)
        let reach: Float = 450 * 450
        let expected = (reach - 300 * 300) / (reach - 0.25 * reach)
        #expect(abs(FocusShadowMath.strength(distance: 300) - expected) < 1e-5)
        #expect(FocusShadowMath.strength(distance: 450) == 0)
    }

    @Test
    func mapSizeHalvesEveryStep() {
        #expect(FocusShadowMath.size(distance: 0, resolution: 4096) == 800)
        #expect(FocusShadowMath.size(distance: 450, resolution: 4096) == 400)
        #expect(FocusShadowMath.size(distance: 1800, resolution: 4096) == 50)
        #expect(FocusShadowMath.size(distance: 3000, resolution: 4096) == 50)
        #expect(FocusShadowMath.size(distance: 0, resolution: 512) == 512)
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
