// Stroke geometry for a shape's line styles: each run of connected edges becomes quads,
// with the style's joins between pieces and its caps on open ends. Rules and limits:
// docs/formats/swf-shapes.md#strokes.

import Foundation
import simd

nonisolated enum SWFShapeStroker {
    /// The thinnest line drawn, in twips: one pixel. Flash draws a thinner line, width 0
    /// included, as a hairline.
    static let hairlineTwips = 20.0
    /// The most a round cap or join's arc may stray from the true circle, in twips.
    static let arcToleranceTwips = 1.0

    /// Triangles for the 1-based line style `index`, three vertices each.
    static func stroke(
        _ shape: SWFShapeDefinition,
        style index: Int,
        flatten: (SWFShapeSegment) -> [SIMD2<Double>]
    ) -> [SIMD2<Float>] {
        var writer = StrokeWriter(style: shape.lineStyles[index - 1])
        for path in paths(of: shape, style: index, flatten: flatten) {
            writer.stroke(path)
        }
        return writer.vertices
    }

    /// Chains edges in file order: an edge that starts where the last one ended continues
    /// the same path, so its joint gets a join rather than two caps.
    private static func paths(
        of shape: SWFShapeDefinition,
        style: Int,
        flatten: (SWFShapeSegment) -> [SIMD2<Double>]
    ) -> [[SIMD2<Double>]] {
        var paths: [[SIMD2<Double>]] = []
        var current: [SIMD2<Double>] = []
        for segment in shape.segments where segment.lineStyle == style {
            let points = flatten(segment)
            if let last = current.last, let first = points.first, last == first {
                current.append(contentsOf: points.dropFirst())
            } else {
                paths.append(current)
                current = points
            }
        }
        paths.append(current)
        return paths.map { path in
            path.enumerated().compactMap { offset, point in
                offset > 0 && path[offset - 1] == point ? nil : point
            }
        }.filter { $0.count > 1 }
    }
}

/// Collects the triangles of one line style.
nonisolated private struct StrokeWriter {
    let style: SWFLineStyle
    let half: Double
    var vertices: [SIMD2<Float>] = []

    init(style: SWFLineStyle) {
        self.style = style
        half = max(Double(style.width), SWFShapeStroker.hairlineTwips) / 2
    }

    mutating func stroke(_ path: [SIMD2<Double>]) {
        for index in 0 ..< path.count - 1 {
            let start = path[index], end = path[index + 1]
            let side = Self.normal(end - start) * half
            quad(start + side, end + side, end - side, start - side)
        }
        for index in 1 ..< path.count - 1 {
            join(path[index - 1], path[index], path[index + 1])
        }
        if path.count > 2, path.first == path.last {
            if !style.noClose {
                join(path[path.count - 2], path[0], path[1])
            }
            return
        }
        let last = path.count - 1
        cap(style.startCap, at: path[0], away: path[0] - path[1])
        cap(style.endCap, at: path[last], away: path[last] - path[last - 1])
    }

    private static func normal(_ direction: SIMD2<Double>) -> SIMD2<Double> {
        let unit = simd_normalize(direction)
        return SIMD2(-unit.y, unit.x)
    }

    /// Fills the gap on the outer side of a turn. The pieces already cover the inner side.
    private mutating func join(
        _ previous: SIMD2<Double>, _ joint: SIMD2<Double>, _ next: SIMD2<Double>
    ) {
        let incoming = simd_normalize(joint - previous)
        let outgoing = simd_normalize(next - joint)
        let turn = incoming.x * outgoing.y - incoming.y * outgoing.x
        guard abs(turn) > 1e-9 || simd_dot(incoming, outgoing) < 0 else { return }
        let sign: Double = turn > 0 ? -1 : 1
        let outward = Self.normal(incoming) * sign
        let first = joint + outward * half
        let second = joint + Self.normal(outgoing) * sign * half
        switch style.join {
        case .round:
            disc(at: joint)
        case .bevel:
            triangle(joint, first, second)
        case let .miter(limit):
            let middle = simd_normalize(first + second - joint * 2)
            let cosine = simd_dot(middle, outward)
            let length = cosine > 1e-6 ? half / cosine : .infinity
            if length <= half * Double(max(limit, 1)) {
                quad(joint, first, joint + middle * length, second)
            } else {
                triangle(joint, first, second)
            }
        }
    }

    private mutating func cap(
        _ cap: SWFLineStyle.CapStyle, at point: SIMD2<Double>, away: SIMD2<Double>
    ) {
        switch cap {
        case .none:
            break
        case .round:
            disc(at: point)
        case .square:
            let outward = simd_normalize(away) * half
            let side = SIMD2(-outward.y, outward.x)
            quad(point + side, point + side + outward, point - side + outward, point - side)
        }
    }

    /// A polygon whose edges stray from the circle by at most the arc tolerance.
    private mutating func disc(at centre: SIMD2<Double>) {
        let ratio = max(-1, min(1, 1 - SWFShapeStroker.arcToleranceTwips / half))
        let steps = max(8, min(64, Int(ceil(Double.pi / max(acos(ratio), 1e-3)))))
        for step in 0 ..< steps {
            let from = Double(step) / Double(steps) * 2 * Double.pi
            let to = Double(step + 1) / Double(steps) * 2 * Double.pi
            triangle(
                centre,
                centre + SIMD2(cos(from), sin(from)) * half,
                centre + SIMD2(cos(to), sin(to)) * half
            )
        }
    }

    private mutating func quad(
        _ first: SIMD2<Double>, _ second: SIMD2<Double>, _ third: SIMD2<Double>,
        _ fourth: SIMD2<Double>
    ) {
        triangle(first, second, third)
        triangle(first, third, fourth)
    }

    private mutating func triangle(
        _ first: SIMD2<Double>, _ second: SIMD2<Double>, _ third: SIMD2<Double>
    ) {
        vertices.append(SIMD2<Float>(first))
        vertices.append(SIMD2<Float>(second))
        vertices.append(SIMD2<Float>(third))
    }
}
