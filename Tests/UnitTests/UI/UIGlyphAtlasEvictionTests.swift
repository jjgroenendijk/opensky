// Eviction tests for the shared glyph atlas (issue #127): a fixed-size atlas
// shared by every movie must hand cells back when a movie is released, or a
// host that swaps movies exhausts the shelf and later text vanishes. Fixtures
// are synthetic rectangle paths — no game content, no CoreText dependency.

import CoreGraphics
@testable import opensky
import Testing

struct UIGlyphAtlasEvictionTests {
    /// SWF font keys carry the movie generation in the high bits, which is what
    /// the renderer evicts by; mirror that layout here.
    private static func fontKey(generation: Int, font: Int = 0) -> Int {
        (generation << SWFTextPlanner.generationShift) | font
    }

    private static func squarePath(side: Int) -> CGPath {
        CGPath(
            rect: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)),
            transform: nil
        )
    }

    /// Packs `count` distinct square glyphs for one generation, returning how
    /// many produced a non-empty entry.
    @discardableResult
    private static func packSquares(
        into atlas: UIGlyphAtlas,
        generation: Int,
        count: Int,
        side: Int = 24
    ) -> Int {
        var packed = 0
        for index in 0 ..< count {
            let entry = atlas.swfEntry(
                fontKey: fontKey(generation: generation),
                glyphIndex: index,
                emPixelSize: side
            ) { squarePath(side: side) }
            if !entry.isEmpty {
                packed += 1
            }
        }
        return packed
    }

    @Test func packingBeyondCapacityIsCountedNotOverrun() {
        let atlas = UIGlyphAtlas()
        // 512x512 atlas, 26x26 cells with padding -> well over capacity.
        let packed = Self.packSquares(into: atlas, generation: 1, count: 600)
        #expect(atlas.packFailures > 0)
        #expect(packed < 600)
        #expect(atlas.occupancy <= 1)
    }

    @Test func releasingAGenerationReclaimsItsCells() {
        let atlas = UIGlyphAtlas()
        Self.packSquares(into: atlas, generation: 1, count: 600)
        #expect(atlas.packFailures > 0)
        let occupied = atlas.occupancy

        let dropped = atlas.releaseSWFGlyphs { key in
            SWFTextPlanner.generation(forFontKey: key) == 1
        }
        #expect(dropped > 0)
        #expect(atlas.packedGlyphCount == 0)
        #expect(atlas.occupancy == 0)
        #expect(atlas.packFailures == 0)
        #expect(occupied > 0)

        // A later movie packs into the reclaimed space instead of being dropped.
        let packedAfter = Self.packSquares(into: atlas, generation: 2, count: 100)
        #expect(packedAfter == 100)
        #expect(atlas.packFailures == 0)
    }

    @Test func releaseKeepsOtherGenerationsRenderable() {
        let atlas = UIGlyphAtlas()
        Self.packSquares(into: atlas, generation: 1, count: 40, side: 20)
        let survivor = atlas.swfEntry(
            fontKey: Self.fontKey(generation: 2), glyphIndex: 0, emPixelSize: 32
        ) { Self.squarePath(side: 32) }
        #expect(!survivor.isEmpty)

        atlas.releaseSWFGlyphs { SWFTextPlanner.generation(forFontKey: $0) == 1 }
        #expect(atlas.packedGlyphCount == 1)

        // The survivor keeps its metrics, moves in the atlas, and its coverage
        // follows it: the cell's centre texel is still opaque.
        let repacked = atlas.swfEntry(
            fontKey: Self.fontKey(generation: 2), glyphIndex: 0, emPixelSize: 32
        ) { Issue.record("survivor was re-rasterized")
            return nil
        }
        #expect(repacked.size == survivor.size)
        #expect(repacked.bearing == survivor.bearing)
        let centreX = Int((repacked.uvMin.x + repacked.uvMax.x) / 2 * Float(atlas.width))
        let centreY = Int((repacked.uvMin.y + repacked.uvMax.y) / 2 * Float(atlas.height))
        #expect(atlas.pixels[centreY * atlas.width + centreX] == 255)
    }

    @Test func releasePreservesTheWhiteBlockAndBumpsRevision() {
        let atlas = UIGlyphAtlas()
        Self.packSquares(into: atlas, generation: 1, count: 10)
        let revision = atlas.revision
        atlas.releaseSWFGlyphs { SWFTextPlanner.generation(forFontKey: $0) == 1 }
        #expect(atlas.revision > revision)
        let whiteX = Int(atlas.whiteUV.x * Float(atlas.width))
        let whiteY = Int(atlas.whiteUV.y * Float(atlas.height))
        #expect(atlas.pixels[whiteY * atlas.width + whiteX] == 255)
    }

    @Test func releasingAnUnrelatedGenerationChangesNothing() {
        let atlas = UIGlyphAtlas()
        Self.packSquares(into: atlas, generation: 1, count: 10)
        let pixels = atlas.pixels
        let revision = atlas.revision
        let dropped = atlas.releaseSWFGlyphs { SWFTextPlanner.generation(forFontKey: $0) == 9 }
        #expect(dropped == 0)
        #expect(atlas.revision == revision)
        #expect(atlas.pixels == pixels)
    }

    @Test func repackIsDeterministic() {
        func atlasAfterRelease() -> [UInt8] {
            let atlas = UIGlyphAtlas()
            Self.packSquares(into: atlas, generation: 1, count: 30, side: 18)
            Self.packSquares(into: atlas, generation: 2, count: 30, side: 26)
            atlas.releaseSWFGlyphs { SWFTextPlanner.generation(forFontKey: $0) == 1 }
            return atlas.pixels
        }
        #expect(atlasAfterRelease() == atlasAfterRelease())
    }
}
