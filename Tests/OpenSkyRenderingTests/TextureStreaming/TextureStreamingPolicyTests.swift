// The distance rule and the budget fit that choose each streamed texture's level.

import OpenSkyRendering
import Testing

struct TextureStreamingPolicyTests {
    /// 1000 pixels high with a 90 degree field of view: one unit `d` units away is
    /// `500 / d` pixels tall.
    private let view = TextureStreamingView(viewHeight: 1000, tanHalfFOV: 1)

    private func layout(tail: Int = 3) -> SparseTextureLayout {
        SparseTextureLayout(
            size: SIMD2(1024, 1024), mipCount: 11, tileSize: SIMD2(128, 128),
            tail: (firstLevel: tail, tiles: 1)
        )
    }

    @Test func aCloseSurfaceNeedsTheFullTexture() {
        // One repeat per 1000 units at 100 units away: 5 pixels and 1.024 texels per unit.
        let level = TextureStreamingPolicy.neededLevel(
            textureSize: 1024, uvPerUnit: 0.001, distance: 100, view: view
        )
        #expect(level == 0)
    }

    @Test func aFarSurfaceDropsLevelsLessTheMargin() {
        // One repeat per 100 units at 1000 units away: 0.5 pixels and 10.24 texels per
        // unit, a ratio of 20.48, so 4 levels less the margin of 1.
        let level = TextureStreamingPolicy.neededLevel(
            textureSize: 1024, uvPerUnit: 0.01, distance: 1000, view: view
        )
        #expect(level == 3)
    }

    @Test func denserUVsNeedMoreTexels() {
        let once = TextureStreamingPolicy.neededLevel(
            textureSize: 1024, uvPerUnit: 0.01, distance: 1000, view: view
        )
        let fourTimes = TextureStreamingPolicy.neededLevel(
            textureSize: 1024, uvPerUnit: 0.04, distance: 1000, view: view
        )
        #expect(fourTimes == once + 2)
    }

    @Test func demandsWithinTheBudgetKeepTheirLevels() {
        let demands = [
            TextureDemand(layout: layout(), wantedLevel: 0, distance: 10),
            TextureDemand(layout: layout(), wantedLevel: 9, distance: 20)
        ]
        // Level 0 is 64 + 16 + 4 tiles plus the tail; the floor of the second is level 3.
        #expect(TextureStreamingPolicy.fit(demands, budgetTiles: 1000) == [0, 3])
    }

    @Test func theFarthestTextureDropsFirst() {
        let demands = [
            TextureDemand(layout: layout(), wantedLevel: 0, distance: 10),
            TextureDemand(layout: layout(), wantedLevel: 0, distance: 500)
        ]
        // 85 tiles each. One drop of the far texture (64 tiles) fits 120.
        #expect(TextureStreamingPolicy.fit(demands, budgetTiles: 120) == [0, 1])
        // 100 needs a second drop, which the near texture takes before the far drops again.
        #expect(TextureStreamingPolicy.fit(demands, budgetTiles: 100) == [1, 1])
    }

    @Test func floorsCanExceedTheBudget() {
        let demands = [TextureDemand(layout: layout(), wantedLevel: 0, distance: 10)]
        #expect(TextureStreamingPolicy.fit(demands, budgetTiles: 0) == [3])
    }
}
