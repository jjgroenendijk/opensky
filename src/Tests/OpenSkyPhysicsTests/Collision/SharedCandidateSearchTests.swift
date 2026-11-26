// One search over a region serves every query inside it; a query outside searches again.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
import simd
import Testing

struct SharedCandidateSearchTests {
    private static func box(at x: Float) -> StaticCollisionShape {
        StaticCollisionShape(
            reference: FormID(0x900),
            transform: MatrixMath.translation(SIMD3(x, 0, 0)),
            geometry: .box(halfExtents: SIMD3(repeating: 4)),
            bounds: ModelBounds(min: SIMD3(x - 4, -4, -4), max: SIMD3(x + 4, 4, 4))
        )
    }

    @Test func queriesInsideTheRegionFilterTheOneSearch() {
        var asked: [ModelBounds] = []
        let shared = SharedCandidateSearch { bounds in
            asked.append(bounds)
            return [Self.box(at: 0), Self.box(at: 50)]
        }
        shared.cover(ModelBounds(min: SIMD3(-100, -100, -100), max: SIMD3(100, 100, 100)))
        let near = shared.query(ModelBounds(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1)))
        #expect(near.map(\.bounds.min.x) == [-4])
        #expect(shared.searches == 1)
        _ = shared.query(ModelBounds(min: SIMD3(90, -1, -1), max: SIMD3(110, 1, 1)))
        #expect(shared.searches == 2, "a query past the region searches")
        #expect(asked.count == 2)
    }

    @Test func theRegionHoldsTheWholeBodyAndItsTravel() throws {
        var body = try #require(LongBodyShape(halfExtents: SIMD3(15.23, 62.27, 28.42)))
        body.stepHeight = 18
        let region = body.searchRegion(at: [0, 0, 100], yaw: 0, travel: 20)
        for end in body.endFeet(at: [20, 0, 100], yaw: 0, lift: 0) {
            #expect(region.min.x < end.x - body.endRadius && region.max.x > end.x + body.endRadius)
        }
        #expect(region.min.z <= 100 - LongBodyShape.searchDepth)
        #expect(region.max.z > 100 + body.bodyHeight + body.bodyRadius + 18)
    }
}
