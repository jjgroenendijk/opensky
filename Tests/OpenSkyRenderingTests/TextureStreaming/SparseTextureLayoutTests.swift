// How a sparse texture's levels split into tiles and a packed tail.

import OpenSkyRendering
import Testing

struct SparseTextureLayoutTests {
    /// A 2048 x 1024 BC1 texture: 256 x 128 tiles, levels 4 and smaller in a 2-tile tail.
    private let layout = SparseTextureLayout(
        size: SIMD2(2048, 1024), mipCount: 12, tileSize: SIMD2(256, 128),
        tail: (firstLevel: 4, tiles: 2)
    )

    @Test func levelsAboveTheTailCountWholeTiles() {
        #expect(layout.tileGrid(level: 0) == SIMD2(8, 8))
        #expect(layout.tiles(level: 0) == 64)
        #expect(layout.tiles(level: 1) == 16)
        #expect(layout.tiles(level: 2) == 4)
        // 256 x 128 is one tile; 128 x 64 still takes a whole one.
        #expect(layout.tiles(level: 3) == 1)
        #expect(layout.tiles(level: 4) == 0)
    }

    @Test func aLevelKeepsEverySmallerLevelAndTheTail() {
        #expect(layout.tiles(fromLevel: 0) == 64 + 16 + 4 + 1 + 2)
        #expect(layout.tiles(fromLevel: 3) == 3)
        #expect(layout.tiles(fromLevel: 4) == 2)
        #expect(layout.tiles(fromLevel: 9) == 2)
    }

    @Test func theFloorIsTheTail() {
        #expect(layout.floorLevel == 4)
        let allTail = SparseTextureLayout(
            size: SIMD2(64, 64), mipCount: 3, tileSize: SIMD2(128, 128),
            tail: (firstLevel: 9, tiles: 1)
        )
        #expect(allTail.firstLevelInTail == 3)
        #expect(allTail.floorLevel == 2)
    }

    @Test func theFittingLevelStopsAtTheFloor() {
        #expect(layout.level(fittingWithin: 4096) == 0)
        #expect(layout.level(fittingWithin: 512) == 2)
        #expect(layout.level(fittingWithin: 1) == 4)
    }
}
