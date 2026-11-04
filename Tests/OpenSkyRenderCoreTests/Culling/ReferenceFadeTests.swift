// Distance fades of placed references by category and size.

@testable import OpenSkyRenderCore
import Testing

struct ReferenceFadeTests {
    let fades = ReferenceFadeDistances(actors: 10, items: 5, objects: 15)
    let lower = SIMD3<Float>(-64, -64, -64)
    let upper = SIMD3<Float>(64, 64, 64)

    @Test
    func reachGrowsWithRadiusAndMultiplier() throws {
        let small = try #require(fades.reach(.object, radius: 1))
        #expect(small == 15 * 16 * 32)
        #expect(fades.reach(.object, radius: 100) == Float(15 * 16 * 100))
        #expect(fades.reach(.none, radius: 100) == nil)
    }

    @Test
    func nearReferenceIsWholeAndFarOneIsGone() throws {
        let radius = Float(3).squareRoot() * 64
        let reach = 10 * 16 * radius
        #expect(fades.fade(.actor, lower: lower, upper: upper, viewer: .zero) == 0)
        let far = SIMD3<Float>(reach + 1, 0, 0)
        #expect(fades.fade(.actor, lower: lower, upper: upper, viewer: far) == nil)
        let edge = SIMD3<Float>(reach * 0.95, 0, 0)
        let fade = try #require(fades.fade(.actor, lower: lower, upper: upper, viewer: edge))
        #expect(fade > 0.6 && fade < 0.7)
    }

    @Test
    func zeroMultiplierNeverFades() {
        let viewer = SIMD3<Float>(1e6, 0, 0)
        #expect(ReferenceFadeDistances.off.isOn == false)
        #expect(ReferenceFadeDistances.off.fade(
            .object,
            lower: lower,
            upper: upper,
            viewer: viewer
        ) == 0)
    }
}
