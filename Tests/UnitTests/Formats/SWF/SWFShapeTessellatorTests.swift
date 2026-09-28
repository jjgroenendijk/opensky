// Unit tests for the shape tessellator: filled area correctness for simple
// polygons, fill0/fill1 side handling, holes under the even-odd rule, shared
// interior edges, deterministic curve flattening, and the per-character
// cache.

import Foundation
@testable import opensky
import Testing

struct SWFShapeTessellatorTests {
    private let red = SWFColor(red: 255, green: 0, blue: 0, alpha: 255)

    /// Signed area sum of a run's triangles (absolute value per triangle).
    private func area(of mesh: SWFShapeMesh, run: SWFShapeMesh.FillRun) -> Double {
        var total = 0.0
        for triangle in run.triangleRange {
            let first = mesh.vertices[triangle * 3]
            let second = mesh.vertices[triangle * 3 + 1]
            let third = mesh.vertices[triangle * 3 + 2]
            let doubled = Double(second.x - first.x) * Double(third.y - first.y)
                - Double(third.x - first.x) * Double(second.y - first.y)
            total += abs(doubled) / 2
        }
        return total
    }

    private func lineSegment(
        from: (Int32, Int32),
        to: (Int32, Int32),
        fill0: Int = 0,
        fill1: Int = 0
    ) -> SWFShapeSegment {
        SWFShapeSegment(
            fromX: from.0,
            fromY: from.1,
            edge: .line(toX: to.0, toY: to.1),
            fillStyle0: fill0,
            fillStyle1: fill1,
            lineStyle: 0
        )
    }

    private func shape(
        segments: [SWFShapeSegment],
        fills: Int = 1,
        windingRule: Bool = false
    ) -> SWFShapeDefinition {
        SWFShapeDefinition(
            characterId: 1,
            bounds: SWFRect(xMin: 0, xMax: 0, yMin: 0, yMax: 0),
            edgeBounds: nil,
            usesFillWindingRule: windingRule,
            fillStyles: Array(repeating: .solid(red), count: fills),
            lineStyles: [],
            segments: segments
        )
    }

    @Test func squareWithFill1YieldsTwoTrianglesOfFullArea() {
        let square = shape(segments: [
            lineSegment(from: (0, 0), to: (100, 0), fill1: 1),
            lineSegment(from: (100, 0), to: (100, 100), fill1: 1),
            lineSegment(from: (100, 100), to: (0, 100), fill1: 1),
            lineSegment(from: (0, 100), to: (0, 0), fill1: 1)
        ])
        let mesh = SWFShapeTessellator.tessellate(square)
        #expect(mesh.runs.count == 1)
        #expect(mesh.runs[0].fillStyleIndex == 1)
        #expect(mesh.triangleCount == 2)
        #expect(abs(area(of: mesh, run: mesh.runs[0]) - 10000) < 0.001)
    }

    @Test func fill0SideProducesTheSameFilledArea() {
        // Same square, but the fill sits on fill0 (left of travel) with the
        // contour wound the opposite way.
        let square = shape(segments: [
            lineSegment(from: (0, 0), to: (0, 100), fill0: 1),
            lineSegment(from: (0, 100), to: (100, 100), fill0: 1),
            lineSegment(from: (100, 100), to: (100, 0), fill0: 1),
            lineSegment(from: (100, 0), to: (0, 0), fill0: 1)
        ])
        let mesh = SWFShapeTessellator.tessellate(square)
        #expect(mesh.runs.count == 1)
        #expect(abs(area(of: mesh, run: mesh.runs[0]) - 10000) < 0.001)
    }

    @Test func evenOddRuleCutsHole() {
        // 100x100 outer square with a 20x20 inner square: even-odd leaves the
        // inner region unfilled regardless of contour orientation.
        var segments = [
            lineSegment(from: (0, 0), to: (100, 0), fill1: 1),
            lineSegment(from: (100, 0), to: (100, 100), fill1: 1),
            lineSegment(from: (100, 100), to: (0, 100), fill1: 1),
            lineSegment(from: (0, 100), to: (0, 0), fill1: 1)
        ]
        segments += [
            lineSegment(from: (40, 40), to: (60, 40), fill1: 1),
            lineSegment(from: (60, 40), to: (60, 60), fill1: 1),
            lineSegment(from: (60, 60), to: (40, 60), fill1: 1),
            lineSegment(from: (40, 60), to: (40, 40), fill1: 1)
        ]
        let mesh = SWFShapeTessellator.tessellate(shape(segments: segments))
        #expect(abs(area(of: mesh, run: mesh.runs[0]) - (10000 - 400)) < 0.001)
    }

    @Test func windingRuleFillsSameOrientationOverlap() {
        // Two same-orientation squares: winding 2 in the overlap. Nonzero
        // fills it; even-odd would cut it out.
        var segments = [
            lineSegment(from: (0, 0), to: (100, 0), fill1: 1),
            lineSegment(from: (100, 0), to: (100, 100), fill1: 1),
            lineSegment(from: (100, 100), to: (0, 100), fill1: 1),
            lineSegment(from: (0, 100), to: (0, 0), fill1: 1)
        ]
        segments += [
            lineSegment(from: (40, 40), to: (60, 40), fill1: 1),
            lineSegment(from: (60, 40), to: (60, 60), fill1: 1),
            lineSegment(from: (60, 60), to: (40, 60), fill1: 1),
            lineSegment(from: (40, 60), to: (40, 40), fill1: 1)
        ]
        let mesh = SWFShapeTessellator.tessellate(
            shape(segments: segments, windingRule: true)
        )
        #expect(abs(area(of: mesh, run: mesh.runs[0]) - 10000) < 0.001)
    }

    @Test func sharedInteriorEdgeSplitsFillsWithoutGaps() throws {
        // A 100x100 rectangle split down the middle: left half fill 1, right
        // half fill 2. The shared vertical edge carries fill0 = 2 (left of
        // upward travel is the right half) and fill1 = 1.
        let segments = [
            lineSegment(from: (0, 0), to: (50, 0), fill1: 1),
            lineSegment(from: (50, 0), to: (100, 0), fill1: 2),
            lineSegment(from: (100, 0), to: (100, 100), fill1: 2),
            lineSegment(from: (100, 100), to: (50, 100), fill1: 2),
            lineSegment(from: (50, 100), to: (50, 0), fill0: 2, fill1: 1),
            lineSegment(from: (50, 100), to: (0, 100), fill0: 1),
            lineSegment(from: (0, 100), to: (0, 0), fill0: 1)
        ]
        let mesh = SWFShapeTessellator.tessellate(shape(segments: segments, fills: 2))
        #expect(mesh.runs.count == 2)
        let leftRun = try #require(mesh.runs.first { $0.fillStyleIndex == 1 })
        let rightRun = try #require(mesh.runs.first { $0.fillStyleIndex == 2 })
        #expect(abs(area(of: mesh, run: leftRun) - 5000) < 0.001)
        #expect(abs(area(of: mesh, run: rightRun) - 5000) < 0.001)
    }

    @Test func curvedEdgeFlattensDeterministicallyAndApproximatesArea() {
        // Region under the quadratic from (0,0) to (100,0) with control
        // (50,100), closed by the base line. Exact area under the curve
        // relative to the chord is 2/3 * base * control-height / 2 ... the
        // enclosed area is (2/3) * 100 * 50 = 3333.33 twips^2.
        let curve = SWFShapeSegment(
            fromX: 0,
            fromY: 0,
            edge: .quadratic(controlX: 50, controlY: 100, toX: 100, toY: 0),
            fillStyle0: 0,
            fillStyle1: 1,
            lineStyle: 0
        )
        let base = lineSegment(from: (100, 0), to: (0, 0), fill1: 1)
        let definition = shape(segments: [curve, base])
        let mesh = SWFShapeTessellator.tessellate(definition)
        let meshAgain = SWFShapeTessellator.tessellate(definition)
        #expect(mesh == meshAgain)
        let filled = area(of: mesh, run: mesh.runs[0])
        // The inscribed polygon under-covers by at most 2/3 * chordTolerance
        // * baseLength = 2/3 * 1 * 100 twips^2 for a 1-twip flattening
        // tolerance.
        #expect(abs(filled - 3333.33) < 67)
    }

    @Test func unfilledSegmentsProduceNoTriangles() {
        let openLine = shape(segments: [lineSegment(from: (0, 0), to: (100, 0))])
        let mesh = SWFShapeTessellator.tessellate(openLine)
        #expect(mesh.vertices.isEmpty)
        #expect(mesh.runs.isEmpty)
    }

    @Test func cacheReturnsSameMeshWithoutRetessellating() {
        let square = shape(segments: [
            lineSegment(from: (0, 0), to: (100, 0), fill1: 1),
            lineSegment(from: (100, 0), to: (100, 100), fill1: 1),
            lineSegment(from: (100, 100), to: (0, 100), fill1: 1),
            lineSegment(from: (0, 100), to: (0, 0), fill1: 1)
        ])
        let cache = SWFShapeCache()
        #expect(cache.cachedMesh(forCharacterId: 1) == nil)
        let first = cache.mesh(for: square)
        #expect(cache.count == 1)
        let second = cache.mesh(for: square)
        #expect(first == second)
        #expect(cache.cachedMesh(forCharacterId: 1) == first)
    }
}
