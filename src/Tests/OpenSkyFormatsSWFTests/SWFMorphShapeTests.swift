// DefineMorphShape and DefineMorphShape2: the start and end forms parse, a ratio
// blends them, and each ratio a timeline places becomes a plain shape character.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFMorphShapeTests {
    private typealias Fixture = SWFMorphShapeFixture

    private func morph(version2: Bool = false) throws -> SWFMorphShapeDefinition {
        let tag = Fixture.tag(characterId: 7, version2: version2)
        return try SWFMorphShapeDefinition.parse(tag: SWFTag(code: tag.code, body: tag.body))
    }

    @Test func bothFormsParse() throws {
        let morph = try morph()
        #expect(morph.characterId == 7)
        #expect(morph.endBounds == SWFRect(xMin: 0, xMax: 300, yMin: 0, yMax: 300))
        #expect(morph.startFillStyles == [.solid(Fixture.startColor)])
        #expect(morph.endFillStyles == [.solid(Fixture.endColor)])
        #expect(morph.endLineStyles.map(\.width) == [Fixture.endWidth])
        #expect(morph.startSegments.count == 4)
        #expect(morph.startSegments.allSatisfy { $0.fillStyle1 == 1 && $0.lineStyle == 1 })
        guard case .quadratic = morph.endSegments.last?.edge else {
            Issue.record("the end form's last edge is not a curve")
            return
        }
    }

    @Test func theSecondVersionReadsEdgeBoundsAndLineFlags() throws {
        let morph = try morph(version2: true)
        #expect(morph.startEdgeBounds == SWFRect(xMin: 0, xMax: 100, yMin: 0, yMax: 100))
        let line = try #require(morph.endLineStyles.first)
        #expect(line.startCap == .none)
        #expect(line.endCap == .square)
        #expect(line.join == .bevel)
        #expect(line.noClose)
        #expect(line.color == Fixture.endColor)
    }

    @Test func theRatioBlendsPointsColoursAndWidths() throws {
        let morph = try morph()
        let start = morph.shape(atRatio: 0, characterId: 1)
        let end = morph.shape(atRatio: .max, characterId: 1)
        let middle = morph.shape(atRatio: 0x8000, characterId: 1)
        #expect(start.segments[1].endPoint == (100, 100))
        #expect(end.segments[1].endPoint == (300, 300))
        #expect(middle.segments[1].endPoint == (200, 200))
        #expect(middle.bounds == SWFRect(xMin: 0, xMax: 200, yMin: 0, yMax: 200))
        #expect(middle.fillStyles == [.solid(SWFColor(red: 100, green: 50, blue: 25, alpha: 155))])
        #expect(middle.lineStyles.map(\.width) == [40])
    }

    @Test func aLinePairedWithACurveBendsAsACurve() throws {
        let start = try morph().shape(atRatio: 0, characterId: 1)
        guard case let .quadratic(controlX, controlY, toX, toY) = start.segments[3].edge else {
            Issue.record("the paired edge stayed a line")
            return
        }
        #expect([controlX, controlY, toX, toY] == [0, 50, 0, 0])
    }

    @Test func formsWithDifferentEdgeCountsFail() {
        let tag = Fixture.tag(characterId: 7, dropEndEdge: true)
        #expect(throws: SWFShapeError.morphEdgeCountMismatch(start: 4, end: 3)) {
            try SWFMorphShapeDefinition.parse(tag: SWFTag(code: tag.code, body: tag.body))
        }
    }

    @Test func eachPlacedRatioBecomesAShape() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            Fixture.tag(characterId: 7),
            SWFDisplayFixture.placeObject2Tag(.init(depth: 1, characterId: 7)),
            SWFDisplayFixture.showFrameTag,
            SWFDisplayFixture.placeObject2Tag(.init(depth: 1, move: true, ratio: .max)),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.characters[7] == nil)
        let first = try #require(movie.frame1.first?.characterId)
        #expect(movie.shape(first)?.bounds.xMax == 100)
        guard case let .place(moved) = movie.timeline.frames[1].steps.first else {
            Issue.record("frame 2 lost its move")
            return
        }
        let second = try #require(moved.characterId)
        #expect(second != first)
        #expect(movie.shape(second)?.bounds.xMax == 300)
    }

    @Test func aSpritesMorphIsExpandedToo() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            Fixture.tag(characterId: 7),
            SWFDisplayFixture.spriteTag(characterId: 8, frameCount: 1, tags: [
                SWFDisplayFixture.placeObject2Tag(.init(depth: 1, characterId: 7, ratio: 0x8000)),
                SWFDisplayFixture.showFrameTag
            ])
        ])
        guard case let .sprite(sprite) = movie.characters[8] else {
            Issue.record("the sprite is gone")
            return
        }
        let id = try #require(sprite.frame1.first?.characterId)
        #expect(movie.shape(id)?.bounds.xMax == 200)
    }
}
