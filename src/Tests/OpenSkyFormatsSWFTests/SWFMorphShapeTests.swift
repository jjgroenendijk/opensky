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

    @Test func aFocalGradientFillKeepsBothFormsAndFocalPoints() throws {
        let red: [UInt8] = [255, 0, 0, 255], blue: [UInt8] = [0, 0, 255, 128]
        // Type, two empty matrices, pad and linear interpolation with 2 stops.
        var bytes: [UInt8] = [0x13, 0x00, 0x00, 0x12]
        bytes += [0] + red + [10] + blue + [255] + blue + [245] + red
        bytes += [0x80, 0x00, 0xC0, 0xFF]
        var bits = SWFBitReader(Data(bytes))
        let fill = try SWFMorphStyleParser.parseFillStyle(&bits)
        guard
            case let .focalRadialGradient(_, start) = fill.start,
            case let .focalRadialGradient(_, end) = fill.end
        else {
            Issue.record("not a focal gradient: \(fill)")
            return
        }
        #expect(start.records.map(\.ratio) == [0, 255])
        #expect(end.records.map(\.ratio) == [10, 245])
        #expect(end.records.first?.color == SWFColor(red: 0, green: 0, blue: 255, alpha: 128))
        #expect(start.interpolationMode == .linearRGB)
        #expect(start.focalPoint == 0.5)
        #expect(end.focalPoint == -0.25)
    }

    @Test func aMiterLineWithAFillReadsTheFillForBothForms() throws {
        // Widths 20 and 40, then miter join with the fill flag, limit 2, a solid fill.
        var bytes: [UInt8] = [20, 0, 40, 0, 0x28, 0x00, 0x00, 0x02, 0x00]
        bytes += [1, 2, 3, 255] + [4, 5, 6, 255]
        var bits = SWFBitReader(Data(bytes))
        let line = try SWFMorphStyleParser.parseLineStyle2(&bits)
        #expect(line.start.width == 20)
        #expect(line.end.width == 40)
        #expect(line.start.join == .miter(limitFactor: 2))
        #expect(line.start.fill == .solid(SWFColor(red: 1, green: 2, blue: 3, alpha: 255)))
        #expect(line.end.fill == .solid(SWFColor(red: 4, green: 5, blue: 6, alpha: 255)))
    }

    @Test func aClippedBitmapFillKeepsItsCharacterForBothForms() throws {
        var bits = SWFBitReader(Data([0x41, 9, 0, 0x00, 0x00]))
        let fill = try SWFMorphStyleParser.parseFillStyle(&bits)
        #expect(fill.start == .bitmap(
            characterId: 9, matrix: .identity, tiled: false, smoothed: true
        ))
        #expect(fill.end == fill.start)
    }

    @Test func aBlendMovesGradientStopsMatricesAndFocalPoints() {
        func gradient(_ ratio: UInt8, _ blue: UInt8, focal: Float) -> SWFGradient {
            SWFGradient(
                spreadMode: .pad, interpolationMode: .normalRGB,
                records: [SWFGradientRecord(
                    ratio: ratio, color: SWFColor(red: 0, green: 0, blue: blue, alpha: 255)
                )],
                focalPoint: focal
            )
        }
        var startMatrix = SWFMatrix.identity
        startMatrix.translateX = 100
        var endMatrix = SWFMatrix.identity
        endMatrix.scaleX = 3
        endMatrix.translateX = 300
        let blended = SWFMorphBlend(weight: 0.5).fill(
            .focalRadialGradient(matrix: startMatrix, gradient: gradient(0, 0, focal: 0)),
            .focalRadialGradient(matrix: endMatrix, gradient: gradient(200, 100, focal: 1))
        )
        guard case let .focalRadialGradient(matrix, middle) = blended else {
            Issue.record("the blend is not a focal gradient: \(blended)")
            return
        }
        #expect(matrix.scaleX == 2)
        #expect(matrix.translateX == 200)
        #expect(middle.records.first?.ratio == 100)
        #expect(middle.records.first?.color.blue == 50)
        #expect(middle.focalPoint == 0.5)
    }
}
