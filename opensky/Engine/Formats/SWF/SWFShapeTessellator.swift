// CPU-side tessellation of decoded SWF shapes into triangle lists, cached per
// character id for the display-list renderer (milestone 8.2.4). GPU upload is
// out of scope here — the mesh is plain twip-space positions grouped by fill.
//
// Method: quadratic Bezier edges are flattened deterministically, then each
// fill style's boundary segments are swept in horizontal bands (a trapezoid
// decomposition). FillStyle0 marks the fill left of an edge's travel
// direction and FillStyle1 the right (spec v19, "FillStyle0 and FillStyle1",
// p. 128), so fill0 edges enter the sweep reversed and every boundary is
// consistently oriented. The default SWF fill rule is even-odd; DefineShape4
// can request the winding (nonzero) rule via UsesFillWindingRule (spec
// p. 133). An edge with the same fill on both sides contributes both
// directions, which cancels under either rule — interior edges do not split
// the fill. Line styles are decoded but not stroke-tessellated yet (deferral
// documented in docs/formats/swf.md).

import Foundation
import simd

/// Triangle mesh for one shape, in twips. Three consecutive `vertices`
/// entries form one triangle; `runs` groups consecutive triangles by fill.
nonisolated struct SWFShapeMesh: Equatable {
    struct FillRun: Equatable {
        /// 1-based index into `SWFShapeDefinition.fillStyles`, matching the
        /// segment convention (0 is never emitted — unfilled edges produce no
        /// triangles).
        let fillStyleIndex: Int
        /// Triangle indices (not vertex indices) covered by this fill.
        let triangleRange: Range<Int>
    }

    let vertices: [SIMD2<Float>]
    let runs: [FillRun]

    var triangleCount: Int {
        vertices.count / 3
    }
}

nonisolated enum SWFShapeTessellator {
    /// Flattening tolerance in twips (1/20 px): the maximum distance a
    /// flattened chord may deviate from the true quadratic curve.
    static let curveToleranceTwips = 1.0

    static func tessellate(_ shape: SWFShapeDefinition) -> SWFShapeMesh {
        var usedFills: Set<Int> = []
        for segment in shape.segments {
            if segment.fillStyle0 > 0 {
                usedFills.insert(segment.fillStyle0)
            }
            if segment.fillStyle1 > 0 {
                usedFills.insert(segment.fillStyle1)
            }
        }
        var vertices: [SIMD2<Float>] = []
        var runs: [SWFShapeMesh.FillRun] = []
        for fill in usedFills.sorted() {
            let boundary = boundarySegments(of: shape, fill: fill)
            let start = vertices.count / 3
            sweep(boundary, evenOdd: !shape.usesFillWindingRule, into: &vertices)
            let end = vertices.count / 3
            if end > start {
                runs.append(SWFShapeMesh.FillRun(
                    fillStyleIndex: fill,
                    triangleRange: start ..< end
                ))
            }
        }
        return SWFShapeMesh(vertices: vertices, runs: runs)
    }

    /// A directed straight boundary piece after curve flattening.
    private struct DirectedSegment {
        var start: SIMD2<Double>
        var end: SIMD2<Double>
    }

    /// Collects fill `fill`'s boundary with the interior consistently on one
    /// side: fill1 edges keep their direction, fill0 edges are reversed.
    private static func boundarySegments(
        of shape: SWFShapeDefinition,
        fill: Int
    ) -> [DirectedSegment] {
        var result: [DirectedSegment] = []
        for segment in shape.segments where
            segment.fillStyle0 == fill || segment.fillStyle1 == fill
        {
            let points = flatten(segment)
            for index in 0 ..< points.count - 1 {
                if segment.fillStyle1 == fill {
                    result.append(DirectedSegment(start: points[index], end: points[index + 1]))
                }
                if segment.fillStyle0 == fill {
                    result.append(DirectedSegment(start: points[index + 1], end: points[index]))
                }
            }
        }
        return result
    }

    /// Flattens one edge to a polyline. Straight edges pass through; curves
    /// subdivide uniformly with a step count derived from the control point's
    /// deviation from the chord midpoint (deterministic — no adaptive
    /// floating-point recursion).
    private static func flatten(_ segment: SWFShapeSegment) -> [SIMD2<Double>] {
        let from = SIMD2(Double(segment.fromX), Double(segment.fromY))
        switch segment.edge {
        case let .line(toX, toY):
            return [from, SIMD2(Double(toX), Double(toY))]
        case let .quadratic(controlX, controlY, toX, toY):
            let control = SIMD2(Double(controlX), Double(controlY))
            let to = SIMD2(Double(toX), Double(toY))
            // Max deviation of a quadratic from its chord is
            // |control - midpoint(chord)| / 2; error after n uniform
            // subdivisions falls with n^2.
            let deviation = simd_length(control - (from + to) / 2) / 2
            let steps = max(1, min(64, Int(ceil(sqrt(deviation / curveToleranceTwips)))))
            var points = [from]
            for step in 1 ... steps {
                let progress = Double(step) / Double(steps)
                let inverse = 1 - progress
                let point = from * (inverse * inverse)
                    + control * (2 * inverse * progress)
                    + to * (progress * progress)
                points.append(point)
            }
            return points
        }
    }

    /// One boundary segment prepared for a single band: x at the band's top
    /// and bottom edges plus its winding contribution.
    private struct BandEdge {
        var xTop: Double
        var xBottom: Double
        var winding: Int
    }

    /// Trapezoid sweep: split the y range at every segment endpoint, then in
    /// each band sort the crossing segments by x and fill the spans selected
    /// by the fill rule. Handles holes and disjoint contours without contour
    /// chaining.
    private static func sweep(
        _ segments: [DirectedSegment],
        evenOdd: Bool,
        into vertices: inout [SIMD2<Float>]
    ) {
        let breaks = Set(segments.flatMap { [$0.start.y, $0.end.y] }).sorted()
        guard breaks.count >= 2 else { return }
        for index in 0 ..< breaks.count - 1 {
            let yTop = breaks[index]
            let yBottom = breaks[index + 1]
            var edges: [BandEdge] = []
            for segment in segments {
                let yMin = min(segment.start.y, segment.end.y)
                let yMax = max(segment.start.y, segment.end.y)
                // Bands split at every endpoint, so a non-horizontal segment
                // either spans a band fully or misses it.
                guard yMin <= yTop, yMax >= yBottom, yMax > yMin else { continue }
                let slope = (segment.end.x - segment.start.x) / (segment.end.y - segment.start.y)
                edges.append(BandEdge(
                    xTop: segment.start.x + (yTop - segment.start.y) * slope,
                    xBottom: segment.start.x + (yBottom - segment.start.y) * slope,
                    winding: segment.end.y > segment.start.y ? 1 : -1
                ))
            }
            edges.sort { $0.xTop + $0.xBottom < $1.xTop + $1.xBottom }
            emitSpans(edges: edges, yTop: yTop, yBottom: yBottom, evenOdd: evenOdd, into: &vertices)
        }
    }

    /// Walks a band's sorted edges accumulating winding and emits a trapezoid
    /// (two triangles) for every filled span.
    private static func emitSpans(
        edges: [BandEdge],
        yTop: Double,
        yBottom: Double,
        evenOdd: Bool,
        into vertices: inout [SIMD2<Float>]
    ) {
        func filled(_ winding: Int) -> Bool {
            evenOdd ? winding % 2 != 0 : winding != 0
        }
        var winding = 0
        var openEdge: BandEdge?
        for edge in edges {
            let wasFilled = filled(winding)
            winding += edge.winding
            if !wasFilled, filled(winding) {
                openEdge = edge
            } else if wasFilled, !filled(winding), let left = openEdge {
                appendTrapezoid(
                    left: left,
                    right: edge,
                    yRange: yTop ... yBottom,
                    into: &vertices
                )
                openEdge = nil
            }
        }
    }

    private static func appendTrapezoid(
        left: BandEdge,
        right: BandEdge,
        yRange: ClosedRange<Double>,
        into vertices: inout [SIMD2<Float>]
    ) {
        let topLeft = SIMD2(Float(left.xTop), Float(yRange.lowerBound))
        let topRight = SIMD2(Float(right.xTop), Float(yRange.lowerBound))
        let bottomRight = SIMD2(Float(right.xBottom), Float(yRange.upperBound))
        let bottomLeft = SIMD2(Float(left.xBottom), Float(yRange.upperBound))
        appendTriangle(topLeft, topRight, bottomRight, into: &vertices)
        appendTriangle(topLeft, bottomRight, bottomLeft, into: &vertices)
    }

    private static func appendTriangle(
        _ first: SIMD2<Float>,
        _ second: SIMD2<Float>,
        _ third: SIMD2<Float>,
        into vertices: inout [SIMD2<Float>]
    ) {
        // Skip slivers below half a square twip so degenerate trapezoid sides
        // do not emit zero-area triangles.
        let doubledArea = (second.x - first.x) * (third.y - first.y)
            - (third.x - first.x) * (second.y - first.y)
        guard abs(doubledArea) > 1e-3 else { return }
        vertices.append(first)
        vertices.append(second)
        vertices.append(third)
    }
}

/// Per-character tessellation cache. SWF character ids are unique in a
/// movie's dictionary, so the character id is the cache key; the mesh is
/// computed once and reused by every placement (consumed by 8.2.4).
nonisolated final class SWFShapeCache {
    private var meshes: [UInt16: SWFShapeMesh] = [:]

    var count: Int {
        meshes.count
    }

    /// Returns the cached mesh for the shape's character id, tessellating on
    /// first use.
    func mesh(for shape: SWFShapeDefinition) -> SWFShapeMesh {
        if let cached = meshes[shape.characterId] {
            return cached
        }
        let mesh = SWFShapeTessellator.tessellate(shape)
        meshes[shape.characterId] = mesh
        return mesh
    }

    func cachedMesh(forCharacterId characterId: UInt16) -> SWFShapeMesh? {
        meshes[characterId]
    }
}
