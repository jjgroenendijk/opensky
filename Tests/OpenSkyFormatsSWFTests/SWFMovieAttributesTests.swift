// FileAttributes, Metadata, and DefineScalingGrid: decoding, and the nine-slice
// mapping a gridded sprite's shapes draw with.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFMovieAttributesTests {
    @Test func fileAttributesAndMetadataDecode() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFButtonFixture.fileAttributesTag(flags: 0x19),
            SWFButtonFixture.metadataTag("<rdf/>"),
            SWFDisplayFixture.showFrameTag
        ])
        let attributes = try #require(movie.fileAttributes)
        #expect(attributes.hasMetadata)
        #expect(attributes.isActionScript3)
        #expect(attributes.usesNetwork)
        #expect(!attributes.usesGPU)
        #expect(movie.metadata == "<rdf/>")
    }

    private static func griddedTags(scale: Float) -> [SWFFixture.Tag] {
        var place = SWFDisplayFixture.Place2()
        place.depth = 1
        place.characterId = 2
        place.name = "panel"
        place.matrix = SWFDisplayFixture.MatrixSpec(scaleX: scale, scaleY: 1)
        return [
            SWFRuntimeFixture.rectangle(id: 1, width: 1000, height: 1000),
            SWFDisplayFixture.spriteTag(characterId: 2, frameCount: 1, tags: [
                SWFRuntimeFixture.place(1, depth: 1),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFButtonFixture.scalingGridTag(
                characterId: 2, splitter: SWFRect(xMin: 100, xMax: 900, yMin: 100, yMax: 900)
            ),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.showFrameTag
        ]
    }

    @Test func aScalingGridAttachesToItsSprite() throws {
        let movie = try SWFDisplayFixture.movie(tags: Self.griddedTags(scale: 2))
        #expect(movie.sprite(2)?.scalingGrid == SWFRect(xMin: 100, xMax: 900, yMin: 100, yMax: 900))
    }

    @Test func theCornersKeepTheirSizeAndTheCentreStretches() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.griddedTags(scale: 2))
        let item = try #require(SWFRuntimeFixture.drawItems(runtime.makeScene()).first)
        let grid = try #require(item.scalingGrid)
        // Scaled by 2, the 100-twip left corner must still be 100 twips wide.
        let corner = item.transform.apply(grid.remap(SIMD2(100, 0)))
        let origin = item.transform.apply(grid.remap(SIMD2(0, 0)))
        #expect(abs(corner.x - origin.x - 100) < 0.01)
        let right = item.transform.apply(grid.remap(SIMD2(1000, 0)))
        #expect(abs(right.x - origin.x - 2000) < 0.01)
        // The y axis is not scaled, so it maps to itself.
        #expect(grid.remap(SIMD2(0, 50)).y == 50)
    }

    @Test func aSpriteSmallerThanItsCornersScalesNormally() {
        let mapped = SWFSceneScalingGrid.remap(
            50, span: SIMD2(0, 1000), grid: SIMD2(400, 600), scale: 0.5
        )
        #expect(mapped == 50)
    }
}
