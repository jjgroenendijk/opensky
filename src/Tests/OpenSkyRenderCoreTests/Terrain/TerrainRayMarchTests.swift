// A ray meets flat or sloped land where the height field says, and misses land it
// never reaches.

import OpenSkyRenderCore
import simd
import Testing

struct TerrainRayMarchTests {
    private static func flat(_ height: Float) -> (SIMD2<Float>) -> TerrainGroundSample? {
        { _ in TerrainGroundSample(height: height, normal: SIMD3(0, 0, 1)) }
    }

    @Test func aDownwardRayStopsOnFlatLand() throws {
        let hit = try #require(TerrainRayMarch.firstHit(
            from: SIMD3(0, 0, 60), along: SIMD3(1, 0, -1), within: 512, sample: Self.flat(0)
        ))
        #expect(abs(hit.position.x - 60) < 0.1)
        #expect(hit.position.z == 0)
        #expect(abs(hit.distance - 60 * sqrtf(2)) < 0.1)
        #expect(hit.normal == SIMD3(0, 0, 1))
    }

    @Test func aSlopeRisingToMeetTheRayIsFound() throws {
        let slope: (SIMD2<Float>) -> TerrainGroundSample? = {
            TerrainGroundSample(height: $0.x - 100, normal: simd_normalize(SIMD3(-1, 0, 1)))
        }
        let hit = try #require(TerrainRayMarch.firstHit(
            from: SIMD3(0, 0, 50), along: SIMD3(1, 0, 0), within: 512, sample: slope
        ))
        #expect(abs(hit.position.x - 150) < 0.1)
    }

    @Test func noLandInReachOrAStartUnderGroundGivesNothing() {
        let far = TerrainRayMarch.firstHit(
            from: SIMD3(0, 0, 600), along: SIMD3(1, 0, -1), within: 100, sample: Self.flat(0)
        )
        #expect(far == nil)
        let buried = TerrainRayMarch.firstHit(
            from: SIMD3(0, 0, -5), along: SIMD3(1, 0, 0), within: 100, sample: Self.flat(0)
        )
        #expect(buried == nil)
        let holes = TerrainRayMarch.firstHit(
            from: SIMD3(0, 0, 60), along: SIMD3(0, 0, -1), within: 100, sample: { _ in nil }
        )
        #expect(holes == nil)
        #expect(TerrainRayMarch.firstHit(
            from: .zero, along: .zero, within: 100, sample: Self.flat(0)
        ) == nil)
    }
}
