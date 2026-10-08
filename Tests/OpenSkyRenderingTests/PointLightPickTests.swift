// Per-draw point light pick: same choice as a full stable sort, in fixed storage.

@testable import OpenSkyRendering
import simd
import Testing

struct PointLightPickTests {
    private static func scene(_ positions: [SIMD3<Float>]) -> RenderScene {
        RenderScene(instances: [], pointLights: positions.map {
            RenderPointLight(position: $0, radius: 100, color: .one, falloffExponent: 1)
        })
    }

    @Test func matchesAStableSortOverManyLights() {
        // A fixed scatter on a small grid, so many lights tie on distance.
        let positions = (0 ..< 200).map { (index: Int) -> SIMD3<Float> in
            let x: Int = index * 7 % 41 - 20
            let y: Int = index * 13 % 37 - 18
            return SIMD3<Float>(Float(x), Float(y), 0)
        }
        let scene = Self.scene(positions)
        let probe = SIMD3<Float>(3, -2, 1)
        let expected = positions.indices.sorted { lhs, rhs in
            let lhsDistance = simd_length_squared(positions[lhs] - probe)
            let rhsDistance = simd_length_squared(positions[rhs] - probe)
            return lhsDistance == rhsDistance ? lhs < rhs : lhsDistance < rhsDistance
        }.prefix(8)
        let pick = scene.nearestPointLightPick(to: probe, limit: 8)
        #expect(pick.count == 8)
        #expect((0 ..< pick.count).map { Int(pick.indices[$0]) } == Array(expected))
    }

    @Test func equalDistancesKeepSceneOrder() {
        let scene = Self.scene(Array(repeating: SIMD3<Float>(1, 0, 0), count: 12))
        let pick = scene.nearestPointLightPick(to: .zero, limit: 8)
        #expect((0 ..< pick.count).map { Int(pick.indices[$0]) } == Array(0 ..< 8))
    }

    @Test func fewLightsKeepAllInSceneOrder() {
        let scene = Self.scene([SIMD3(9, 0, 0), SIMD3(1, 0, 0)])
        let pick = scene.nearestPointLightPick(to: .zero, limit: 8)
        #expect(pick.count == 2)
        #expect(pick.indices[0] == 0)
        #expect(pick.indices[1] == 1)
    }

    @Test func zeroLimitPicksNothing() {
        let scene = Self.scene((0 ..< 10).map { SIMD3(Float($0), 0, 0) })
        #expect(scene.nearestPointLightPick(to: .zero, limit: 0) == PointLightPick())
    }
}
