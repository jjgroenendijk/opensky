// Display-list tag decode tests (milestone 8.2.4): CXFORM records, the three
// PlaceObject versions (including PlaceObject3 class-name/filter/blend
// framing), removals, SetBackgroundColor, and the SWFTransform affine math
// with the movie-to-viewport mapping. Synthetic fixtures only.

import Foundation
@testable import opensky
import simd
import Testing

struct SWFColorTransformTests {
    @Test func multiplyOnlyCxformDecodes() throws {
        var writer = SWFBitWriter()
        SWFDisplayFixture.writeCxform(
            &writer,
            SWFDisplayFixture.CxformSpec(multiplyTerms: [256, 128, 0, 256]),
            hasAlpha: true
        )
        var bits = SWFBitReader(writer.bytes())
        let transform = try SWFColorTransform.parse(&bits, hasAlpha: true)
        #expect(transform.multiply == SIMD4(1, 0.5, 0, 1))
        #expect(transform.add == SIMD4(repeating: 0))
    }

    @Test func addOnlyCxformDecodes() throws {
        var writer = SWFBitWriter()
        SWFDisplayFixture.writeCxform(
            &writer,
            SWFDisplayFixture.CxformSpec(addTerms: [255, -255, 0, 51]),
            hasAlpha: true
        )
        var bits = SWFBitReader(writer.bytes())
        let transform = try SWFColorTransform.parse(&bits, hasAlpha: true)
        #expect(transform.multiply == SIMD4(repeating: 1))
        #expect(abs(transform.add.x - 1) < 1e-6)
        #expect(abs(transform.add.y + 1) < 1e-6)
        #expect(abs(transform.add.w - 51.0 / 255) < 1e-6)
    }

    @Test func rgbCxformLeavesAlphaTermsUntouched() throws {
        var writer = SWFBitWriter()
        SWFDisplayFixture.writeCxform(
            &writer,
            SWFDisplayFixture.CxformSpec(multiplyTerms: [128, 128, 128], addTerms: [10, 10, 10]),
            hasAlpha: false
        )
        var bits = SWFBitReader(writer.bytes())
        let transform = try SWFColorTransform.parse(&bits, hasAlpha: false)
        #expect(transform.multiply.w == 1)
        #expect(transform.add.w == 0)
        #expect(transform.multiply.x == 0.5)
    }

    @Test func applyClampsToUnitRange() {
        let transform = SWFColorTransform(
            multiply: SIMD4(2, 1, 1, 1), add: SIMD4(0, -2, 0.25, 0)
        )
        let result = transform.apply(to: SIMD4(0.75, 0.5, 0.5, 1))
        #expect(result == SIMD4(1, 0, 0.75, 1))
    }

    @Test func concatenationMatchesSequentialApplication() {
        let inner = SWFColorTransform(
            multiply: SIMD4(0.5, 1, 0.25, 1), add: SIMD4(0.1, 0, 0.2, 0)
        )
        let outer = SWFColorTransform(
            multiply: SIMD4(0.5, 0.5, 1, 1), add: SIMD4(0.2, 0.1, 0, 0)
        )
        let combined = outer.concatenating(inner)
        let color = SIMD4<Float>(0.4, 0.8, 0.6, 1)
        let sequential = outer.apply(to: inner.apply(to: color))
        let direct = combined.apply(to: color)
        for channel in 0 ..< 4 {
            #expect(abs(sequential[channel] - direct[channel]) < 1e-6)
        }
    }
}

struct SWFPlacementDecodeTests {
    @Test func placeObjectDecodesMatrixAndOptionalCxform() throws {
        let tag = SWFDisplayFixture.placeObjectTag(
            characterId: 7,
            depth: 3,
            matrix: SWFDisplayFixture.MatrixSpec(translateX: 100, translateY: -40),
            cxform: SWFDisplayFixture.CxformSpec(multiplyTerms: [128, 128, 128])
        )
        let placement = try SWFDisplayListParser.parsePlacement(
            tag: SWFTag(code: tag.code, body: tag.body)
        )
        #expect(placement.characterId == 7)
        #expect(placement.depth == 3)
        #expect(placement.isMove == false)
        #expect(placement.matrix?.translateX == 100)
        #expect(placement.matrix?.translateY == -40)
        #expect(placement.colorTransform?.multiply.x == 0.5)
    }

    @Test func placeObjectWithoutCxformDecodes() throws {
        let tag = SWFDisplayFixture.placeObjectTag(characterId: 1, depth: 1)
        let placement = try SWFDisplayListParser.parsePlacement(
            tag: SWFTag(code: tag.code, body: tag.body)
        )
        #expect(placement.colorTransform == nil)
    }

    @Test func placeObject2DecodesEveryField() throws {
        var place = SWFDisplayFixture.Place2()
        place.depth = 12
        place.characterId = 44
        place.matrix = SWFDisplayFixture.MatrixSpec(
            scaleX: 2, scaleY: 0.5, translateX: 200, translateY: 300
        )
        place.cxform = SWFDisplayFixture.CxformSpec(addTerms: [0, 0, 0, -255])
        place.ratio = 9
        place.name = "cursor"
        place.clipDepth = 20
        let tag = SWFDisplayFixture.placeObject2Tag(place)
        let placement = try SWFDisplayListParser.parsePlacement(
            tag: SWFTag(code: tag.code, body: tag.body)
        )
        #expect(placement.depth == 12)
        #expect(placement.characterId == 44)
        #expect(placement.matrix?.scaleX == 2)
        #expect(placement.matrix?.scaleY == 0.5)
        #expect(placement.colorTransform.map { abs($0.add.w + 1) < 1e-6 } == true)
        #expect(placement.ratio == 9)
        #expect(placement.name == "cursor")
        #expect(placement.clipDepth == 20)
    }

    @Test func placeObject2MoveOnlyDecodes() throws {
        var place = SWFDisplayFixture.Place2()
        place.depth = 5
        place.move = true
        place.matrix = SWFDisplayFixture.MatrixSpec(translateX: 10, translateY: 10)
        let tag = SWFDisplayFixture.placeObject2Tag(place)
        let placement = try SWFDisplayListParser.parsePlacement(
            tag: SWFTag(code: tag.code, body: tag.body)
        )
        #expect(placement.isMove)
        #expect(placement.characterId == nil)
    }

    @Test func placeObject3DecodesClassNameFiltersAndBlend() throws {
        var place3 = SWFDisplayFixture.Place3()
        place3.place.depth = 2
        place3.place.characterId = 6
        place3.place.clipDepth = 8
        place3.className = "Widget"
        place3.blendMode = 3
        place3.blurFilterCount = 2
        let tag = SWFDisplayFixture.placeObject3Tag(place3)
        let placement = try SWFDisplayListParser.parsePlacement(
            tag: SWFTag(code: tag.code, body: tag.body)
        )
        #expect(placement.className == "Widget")
        #expect(placement.blendMode == 3)
        #expect(placement.filterCount == 2)
        #expect(placement.clipDepth == 8)
        #expect(placement.characterId == 6)
    }

    @Test func removalsDecode() throws {
        let removeTag = SWFDisplayFixture.removeObjectTag(characterId: 4, depth: 9)
        let removal = try SWFDisplayListParser.parseRemoval(
            tag: SWFTag(code: removeTag.code, body: removeTag.body)
        )
        #expect(removal.depth == 9)
        #expect(removal.characterId == 4)
        let remove2Tag = SWFDisplayFixture.removeObject2Tag(depth: 11)
        let removal2 = try SWFDisplayListParser.parseRemoval(
            tag: SWFTag(code: remove2Tag.code, body: remove2Tag.body)
        )
        #expect(removal2.depth == 11)
        #expect(removal2.characterId == nil)
    }

    @Test func backgroundColorDecodes() throws {
        let tag = SWFDisplayFixture.backgroundColorTag(
            SWFColor(red: 10, green: 20, blue: 30, alpha: 255)
        )
        let color = try SWFDisplayListParser.parseBackgroundColor(
            tag: SWFTag(code: tag.code, body: tag.body)
        )
        #expect(color == SWFColor(red: 10, green: 20, blue: 30, alpha: 255))
    }

    @Test func truncatedPlacementThrows() {
        let tag = SWFTag(code: 26, body: Data([0x02]))
        #expect(throws: (any Error).self) {
            try SWFDisplayListParser.parsePlacement(tag: tag)
        }
    }
}

struct SWFTransformTests {
    @Test func matrixLiftMatchesSpecSemantics() {
        var matrix = SWFMatrix.identity
        matrix.scaleX = 2
        matrix.scaleY = 3
        matrix.rotateSkew0 = 0.5
        matrix.rotateSkew1 = 0.25
        matrix.translateX = 100
        matrix.translateY = 200
        let transform = SWFTransform(matrix: matrix)
        // Spec p. 23: x' = x*ScaleX + y*RotateSkew1 + tx.
        let point = transform.apply(SIMD2(10, 20))
        let expectedX: Float = 10 * 2 + 20 * 0.25 + 100
        let expectedY: Float = 10 * 0.5 + 20 * 3 + 200
        #expect(point.x == expectedX)
        #expect(point.y == expectedY)
    }

    @Test func concatenationAppliesInnerFirst() {
        let inner = SWFTransform(scaleX: 2, scaleY: 2, translateX: 10, translateY: 0)
        let outer = SWFTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 5)
        let combined = outer.concatenating(inner)
        let direct = outer.apply(inner.apply(SIMD2(1, 1)))
        #expect(combined.apply(SIMD2(1, 1)) == direct)
    }

    @Test func inversionRoundTrips() throws {
        let transform = SWFTransform(
            scaleX: 2, rotateSkew0: 0.5, rotateSkew1: -1, scaleY: 3,
            translateX: 40, translateY: -7
        )
        let inverse = try #require(transform.inverted)
        let round = inverse.apply(transform.apply(SIMD2(13, -4)))
        #expect(abs(round.x - 13) < 1e-3)
        #expect(abs(round.y + 4) < 1e-3)
    }

    @Test func singularMatrixHasNoInverse() {
        let transform = SWFTransform(
            scaleX: 0, rotateSkew0: 0, rotateSkew1: 0, scaleY: 0,
            translateX: 1, translateY: 1
        )
        #expect(transform.inverted == nil)
    }

    @Test func viewportMappingFitsAndCenters() {
        // 8000x6000 twips (400x300 px) into 480x320: height-limited scale
        // 320/6000, content 426.67 px wide, centered with x offset ~26.67.
        let frame = SWFRect(xMin: 0, xMax: 8000, yMin: 0, yMax: 6000)
        let mapping = SWFViewportMapping.twipsToPixels(
            frameSize: frame, viewportPixels: SIMD2(480, 320)
        )
        let topLeft = mapping.apply(SIMD2(0, 0))
        let bottomRight = mapping.apply(SIMD2(8000, 6000))
        let scale: Float = 320.0 / 6000.0
        let expectedOffsetX: Float = (480.0 - 8000.0 * scale) / 2.0
        let rightGap: Float = 480.0 - bottomRight.x
        #expect(abs(topLeft.y) < 1e-3)
        #expect(abs(bottomRight.y - 320) < 1e-3)
        #expect(abs(topLeft.x - expectedOffsetX) < 1e-3)
        #expect(abs(rightGap - topLeft.x) < 1e-3)
    }

    @Test func viewportMappingHonorsFrameOrigin() {
        let frame = SWFRect(xMin: 1000, xMax: 9000, yMin: 500, yMax: 6500)
        let mapping = SWFViewportMapping.twipsToPixels(
            frameSize: frame, viewportPixels: SIMD2(400, 300)
        )
        let origin = mapping.apply(SIMD2(1000, 500))
        #expect(abs(origin.x - 0) < 1e-3)
        #expect(abs(origin.y - 0) < 1e-3)
    }

    @Test func pixelsToClipMapsCornersToNDC() {
        let clip = SWFViewportMapping.pixelsToClip(viewportPixels: SIMD2(480, 320))
        #expect(clip.apply(SIMD2(0, 0)) == SIMD2(-1, 1))
        #expect(clip.apply(SIMD2(480, 320)) == SIMD2(1, -1))
    }
}
