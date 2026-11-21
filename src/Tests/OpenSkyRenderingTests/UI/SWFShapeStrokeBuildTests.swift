// The renderer's shape build gives a stroked edge a draw run of its line colour. The
// shape is built in code.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
@testable import OpenSkyRendering
import Testing

struct SWFShapeStrokeBuildTests {
    private static let black = SWFColor(red: 0, green: 0, blue: 0, alpha: 255)

    private static func strokedLineTag() -> SWFFixture.Tag {
        var builder = SWFShapeBodyBuilder()
        builder.appendCharacterId(1)
        builder.appendRect(xMin: 0, xMax: 200, yMin: 0, yMax: 40)
        builder.appendStyleCount(0)
        builder.appendStyleCount(1)
        builder.appendLineStyle(width: 40, color: black, rgba: false)
        builder.appendIndexBits(fill: 0, line: 1)
        builder.appendStyleChange(SWFShapeBodyBuilder.StyleChange(moveToX: 0, moveToY: 20, line: 1))
        builder.appendAxisEdge(delta: 200, vertical: false)
        builder.appendEndRecord()
        return SWFFixture.Tag(code: 2, body: builder.build())
    }

    @Test func aStrokedEdgeDrawsInItsLineColour() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            Self.strokedLineTag(),
            SWFDisplayFixture.showFrameTag
        ])
        var builder = SWFMovieResources.ShapeBuilder(scene: SWFMovieScene(movie: movie))
        builder.buildShapes()
        let entry = try #require(builder.shapes[1])
        #expect(entry.runs.count == 1)
        guard case let .solid(color) = entry.runs.first?.fill else {
            Issue.record("the stroke run is not a solid fill")
            return
        }
        #expect(color == SIMD4<Float>(0, 0, 0, 1))
        #expect(entry.vertexCount >= 6, "a round-capped line has a quad and two discs")
        #expect(builder.skipped == 0)
    }
}
