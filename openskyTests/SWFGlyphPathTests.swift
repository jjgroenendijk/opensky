// Unit tests for SWF glyph -> CGPath conversion and the SWF glyph-atlas entry
// path. Verifies coordinate scaling (DefineFont2 vs DefineFont3), the y-flip
// into CoreGraphics space, conversion determinism, and atlas caching.

import CoreGraphics
import Foundation
@testable import opensky
import Testing

struct SWFGlyphPathTests {
    /// A filled right triangle in glyph space (y-down): (0,0)->(200,0)->(0,200).
    private func triangleSegments() -> [SWFShapeSegment] {
        [
            SWFShapeSegment(
                fromX: 0, fromY: 0, edge: .line(toX: 200, toY: 0),
                fillStyle0: 0, fillStyle1: 1, lineStyle: 0
            ),
            SWFShapeSegment(
                fromX: 200, fromY: 0, edge: .line(toX: 0, toY: 200),
                fillStyle0: 0, fillStyle1: 1, lineStyle: 0
            ),
            SWFShapeSegment(
                fromX: 0, fromY: 200, edge: .line(toX: 0, toY: 0),
                fillStyle0: 0, fillStyle1: 1, lineStyle: 0
            )
        ]
    }

    private struct PathStep: Equatable {
        let type: Int32
        let points: [CGPoint]
    }

    private func steps(of path: CGPath) -> [PathStep] {
        var result: [PathStep] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let count = switch element.type {
            case .moveToPoint, .addLineToPoint: 1
            case .addQuadCurveToPoint: 2
            case .addCurveToPoint: 3
            case .closeSubpath: 0
            @unknown default: 0
            }
            let points = (0 ..< count).map { element.points[$0] }
            result.append(PathStep(type: element.type.rawValue, points: points))
        }
        return result
    }

    @Test func flipsYAndScalesToPixels() throws {
        let path = try #require(SWFGlyphPath.makePath(
            segments: triangleSegments(), unitsPerEM: 1024, emPixelSize: 1024
        ))
        // At emPixelSize == unitsPerEM the scale is 1:1; y flips so the glyph's
        // downward extent lands below the baseline (negative y).
        let box = path.boundingBoxOfPath
        #expect(abs(box.minX) < 0.001)
        #expect(abs(box.maxX - 200) < 0.001)
        #expect(abs(box.minY - -200) < 0.001)
        #expect(abs(box.maxY) < 0.001)
    }

    @Test func defineFont3ScalesTwentyTimesSmaller() throws {
        let font2 = try #require(SWFGlyphPath.makePath(
            segments: triangleSegments(), unitsPerEM: 1024, emPixelSize: 200
        ))
        let font3 = try #require(SWFGlyphPath.makePath(
            segments: triangleSegments(), unitsPerEM: 1024 * 20, emPixelSize: 200
        ))
        // Identical glyph coordinates at the same pixel size: DefineFont3's
        // 20x EM square makes the rendered glyph 1/20 the size.
        #expect(abs(font2.boundingBoxOfPath.width - font3.boundingBoxOfPath.width * 20) < 0.01)
    }

    @Test func conversionIsDeterministic() throws {
        let first = try #require(SWFGlyphPath.makePath(
            segments: triangleSegments(), unitsPerEM: 1024, emPixelSize: 64
        ))
        let second = try #require(SWFGlyphPath.makePath(
            segments: triangleSegments(), unitsPerEM: 1024, emPixelSize: 64
        ))
        #expect(steps(of: first) == steps(of: second))
    }

    @Test func emptyGlyphMakesNoPath() {
        #expect(SWFGlyphPath.makePath(segments: [], unitsPerEM: 1024, emPixelSize: 40) == nil)
    }

    @Test func atlasRasterizesSWFGlyphAndCaches() {
        let atlas = UIGlyphAtlas()
        func makePath() -> CGPath? {
            SWFGlyphPath.makePath(
                segments: triangleSegments(), unitsPerEM: 1024, emPixelSize: 400
            )
        }
        let entry = atlas.swfEntry(
            fontKey: 100, glyphIndex: 7, emPixelSize: 400, makePath: makePath
        )
        #expect(!entry.isEmpty)
        #expect(entry.size.x > 0)
        #expect(entry.size.y > 0)

        // Second lookup is a cache hit: the atlas does not repack (revision holds).
        let revisionAfterFirst = atlas.revision
        let cached = atlas.swfEntry(
            fontKey: 100, glyphIndex: 7, emPixelSize: 400, makePath: makePath
        )
        #expect(cached == entry)
        #expect(atlas.revision == revisionAfterFirst)
    }

    @Test func atlasReturnsEmptyForEmptyGlyph() {
        let atlas = UIGlyphAtlas()
        let entry = atlas.swfEntry(
            fontKey: 1, glyphIndex: 0, emPixelSize: 40, makePath: { nil }
        )
        #expect(entry.isEmpty)
    }
}
