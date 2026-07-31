// Immutable median-split AABB BVH over a flat `[ModelBounds]` array. The index
// stores element positions only, so any per-cell collection whose elements
// carry a world-space AABB — static collision shapes, trigger volumes — shares
// one broadphase implementation. Query output is sorted so physics and tests
// see a deterministic candidate order.

import simd

nonisolated struct BoundsSpatialIndex {
    /// Elements per leaf. Small enough that a leaf test is cheap, large enough
    /// that a cell with a handful of shapes does not build a deep tree.
    static let maximumElementsPerLeaf = 4

    private struct Node {
        let bounds: ModelBounds
        let left: Int?
        let right: Int?
        let elementIndices: [Int]
    }

    private var nodes: [Node] = []
    private let root: Int?

    init(bounds: [ModelBounds]) {
        var builder = Builder(bounds: bounds)
        root = builder.build(Array(bounds.indices))
        nodes = builder.nodes
    }

    var nodeCount: Int {
        nodes.count
    }

    /// Indices of every element whose leaf node bounds overlap `bounds`,
    /// ascending. Node bounds prune; the caller still filters exact element
    /// AABBs.
    func query(overlapping bounds: ModelBounds) -> [Int] {
        guard let root else { return [] }
        var result: [Int] = []
        var stack = [root]
        while let index = stack.popLast() {
            let node = nodes[index]
            guard node.bounds.overlaps(bounds) else { continue }
            result.append(contentsOf: node.elementIndices)
            if let left = node.left {
                stack.append(left)
            }
            if let right = node.right {
                stack.append(right)
            }
        }
        return result.sorted()
    }

    private struct Builder {
        let bounds: [ModelBounds]
        var nodes: [Node] = []

        mutating func build(_ indices: [Int]) -> Int? {
            guard let first = indices.first else { return nil }
            let nodeBounds = indices.dropFirst().reduce(bounds[first]) {
                $0.union(bounds[$1])
            }
            if indices.count <= BoundsSpatialIndex.maximumElementsPerLeaf {
                nodes.append(Node(
                    bounds: nodeBounds,
                    left: nil,
                    right: nil,
                    elementIndices: indices.sorted()
                ))
                return nodes.count - 1
            }

            let extent = nodeBounds.max - nodeBounds.min
            let axis = extent.x >= extent.y && extent.x >= extent.z ? 0
                : (extent.y >= extent.z ? 1 : 2)
            let sorted = indices.sorted {
                centroid(of: bounds[$0], axis: axis) < centroid(of: bounds[$1], axis: axis)
            }
            let midpoint = sorted.count / 2
            let placeholder = nodes.count
            nodes.append(Node(bounds: nodeBounds, left: nil, right: nil, elementIndices: []))
            let left = build(Array(sorted[..<midpoint]))
            let right = build(Array(sorted[midpoint...]))
            nodes[placeholder] = Node(
                bounds: nodeBounds,
                left: left,
                right: right,
                elementIndices: []
            )
            return placeholder
        }

        private func centroid(of bounds: ModelBounds, axis: Int) -> Float {
            (bounds.min[axis] + bounds.max[axis]) * 0.5
        }
    }
}
