// Stroke geometry: piece quads, caps, joins, hairlines, and how edges chain into paths.
// Shapes are built in code.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFShapeStrokerTests {
    private let black = SWFColor(red: 0, green: 0, blue: 0, alpha: 255)

    private func line(style: SWFLineStyle, points: [(Int32, Int32)]) -> SWFShapeDefinition {
        let segments = points.indices.dropLast().map { index in
            SWFShapeSegment(
                fromX: points[index].0, fromY: points[index].1,
                edge: .line(toX: points[index + 1].0, toY: points[index + 1].1),
                fillStyle0: 0, fillStyle1: 0, lineStyle: 1
            )
        }
        return SWFShapeDefinition(
            characterId: 1, bounds: SWFRect(xMin: 0, xMax: 0, yMin: 0, yMax: 0),
            edgeBounds: nil, usesFillWindingRule: false, fillStyles: [],
            lineStyles: [style], segments: segments
        )
    }

    private func style(
        width: UInt16 = 40,
        cap: SWFLineStyle.CapStyle,
        join: SWFLineStyle.JoinStyle = .round
    ) -> SWFLineStyle {
        var style = SWFLineStyle(width: width, color: black)
        style.startCap = cap
        style.endCap = cap
        style.join = join
        return style
    }

    private func area(of mesh: SWFShapeMesh) -> Double {
        stride(from: 0, to: mesh.vertices.count, by: 3).reduce(0) { total, index in
            let first = mesh.vertices[index], second = mesh.vertices[index + 1]
            let third = mesh.vertices[index + 2]
            let doubled = Double(second.x - first.x) * Double(third.y - first.y)
                - Double(third.x - first.x) * Double(second.y - first.y)
            return total + abs(doubled) / 2
        }
    }

    @Test func aLineWithoutCapsIsOneQuadAsWideAsItsStyle() {
        let mesh = SWFShapeTessellator.tessellate(line(
            style: style(cap: .none),
            points: [(0, 0), (200, 0)]
        ))
        #expect(mesh.runs.isEmpty)
        #expect(mesh.strokeRuns == [SWFShapeMesh.StrokeRun(
            lineStyleIndex: 1,
            triangleRange: 0 ..< 2
        )])
        #expect(abs(area(of: mesh) - 200 * 40) < 0.5)
    }

    @Test func squareCapsReachHalfTheWidthPastEachEnd() {
        let mesh = SWFShapeTessellator.tessellate(line(
            style: style(cap: .square),
            points: [(0, 0), (200, 0)]
        ))
        #expect(abs(area(of: mesh) - 240 * 40) < 0.5)
    }

    @Test func roundCapsAddADiscAtEachEnd() {
        let mesh = SWFShapeTessellator.tessellate(line(
            style: style(cap: .round),
            points: [(0, 0), (200, 0)]
        ))
        let discs = area(of: mesh) - 200 * 40
        #expect(discs < 2 * Double.pi * 400)
        #expect(discs > 0.9 * 2 * Double.pi * 400)
    }

    /// Width 0 draws one pixel wide, which is 20 twips.
    @Test func aThinLineDrawsAsAHairline() {
        let mesh = SWFShapeTessellator.tessellate(
            line(style: style(width: 0, cap: .none), points: [(0, 0), (200, 0)])
        )
        #expect(abs(area(of: mesh) - 200 * 20) < 0.5)
    }

    /// A closed square: four pieces, and a join at every corner, the first one included.
    @Test func aClosedPathJoinsEveryCornerAndHasNoCaps() {
        let square: [(Int32, Int32)] = [(0, 0), (200, 0), (200, 200), (0, 200), (0, 0)]
        let bevel = SWFShapeTessellator.tessellate(line(
            style: style(cap: .round, join: .bevel),
            points: square
        ))
        #expect(bevel.triangleCount == 4 * 2 + 4)
        let miter = SWFShapeTessellator.tessellate(
            line(style: style(cap: .round, join: .miter(limitFactor: 3)), points: square)
        )
        #expect(miter.triangleCount == 4 * 2 + 4 * 2)
        // Each miter corner fills the 20 by 20 square outside the corner.
        #expect(abs(area(of: miter) - area(of: bevel) - 4 * 200) < 0.5)
        let short = SWFShapeTessellator.tessellate(
            line(style: style(cap: .round, join: .miter(limitFactor: 1)), points: square)
        )
        #expect(short.triangleCount == bevel.triangleCount, "a corner past the limit bevels")
    }

    @Test func aStraightJointNeedsNoJoinAndAGapStartsANewPath() {
        let straight = SWFShapeTessellator.tessellate(
            line(style: style(cap: .none, join: .bevel), points: [(0, 0), (100, 0), (200, 0)])
        )
        #expect(straight.triangleCount == 4)
        var shape = line(style: style(cap: .square), points: [(0, 0), (100, 0)])
        let apart = SWFShapeSegment(
            fromX: 0, fromY: 100, edge: .line(toX: 100, toY: 100),
            fillStyle0: 0, fillStyle1: 0, lineStyle: 1
        )
        shape = SWFShapeDefinition(
            characterId: 1, bounds: shape.bounds, edgeBounds: nil, usesFillWindingRule: false,
            fillStyles: [], lineStyles: shape.lineStyles, segments: shape.segments + [apart]
        )
        #expect(SWFShapeTessellator.tessellate(shape).triangleCount == 2 * (2 + 4))
        #expect(shape.strokedSegmentCount == 2)
    }
}
