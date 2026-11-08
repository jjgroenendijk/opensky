// Skirts along the sides a clip cuts: strips that hang below the land and hide the
// step to a neighbour of another level (docs/engine/distant-lod.md#skirts).

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated extension TerrainLODClipper {
    /// The four sides of an owned cell, each with whether the clip cut it: the cell beyond
    /// is inside the block but drawn by another source.
    struct CutEdges {
        let west: (line: Float, cut: Bool)
        let east: (line: Float, cut: Bool)
        let south: (line: Float, cut: Bool)
        let north: (line: Float, cut: Bool)

        func isCut(_ from: SIMD3<Float>, _ to: SIMD3<Float>) -> Bool {
            let lines = [(0, west), (0, east), (1, south), (1, north)]
            return lines.contains { axis, side in
                side.cut && abs(from[axis] - side.line) < Self.tolerance
                    && abs(to[axis] - side.line) < Self.tolerance
            }
        }

        static let tolerance: Float = 0.01
    }

    /// The vanilla files hang skirts 1000, 2000, 3000, and 4000 units below levels 4, 8,
    /// 16, and 32 (docs/engine/distant-lod.md#skirts); a cut edge gets the same depth.
    static func skirtDepth(level: Int32) -> Float {
        let steps = max(log2(Float(max(level, 2))) - 1, 1)
        return 1000 * steps
    }

    /// A strip hanging down from each polygon edge that lies on a cut side, facing both
    /// ways. It hides the gap to a neighbour of another level, whose edge heights differ.
    static func skirts(
        along polygon: [Vertex], cuts: CutEdges, depth: Float
    ) -> [[Vertex]] {
        var output: [[Vertex]] = []
        for index in polygon.indices {
            let top0 = polygon[index]
            let top1 = polygon[(index + 1) % polygon.count]
            guard
                simd_distance(top0.modelPosition, top1.modelPosition) > CutEdges.tolerance,
                cuts.isCut(top0.modelPosition, top1.modelPosition)
            else { continue }
            let bottom0 = top0.lowered(by: depth)
            let bottom1 = top1.lowered(by: depth)
            output += [[top0, bottom0, top1], [top1, bottom0, bottom1]]
            output += [[top0, top1, bottom0], [top1, bottom1, bottom0]]
        }
        return output
    }

    /// A triangle with area seen from above; a vertical skirt has none.
    static func isGround(_ triangle: [Vertex]) -> Bool {
        guard triangle.count == 3 else { return false }
        let first = triangle[0].modelPosition
        let second = triangle[1].modelPosition - first
        let third = triangle[2].modelPosition - first
        return abs(second.x * third.y - second.y * third.x) > 0.001
    }
}
