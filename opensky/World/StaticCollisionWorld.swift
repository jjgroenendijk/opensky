// Immutable per-cell static collision world (milestone 4.3). NIF geometry is
// placed in world space through REFR x body x shape transforms, then indexed
// by a small AABB BVH. Streaming owns the resulting value beside CellScene;
// removing the cell releases its shapes + index together.

import simd

nonisolated struct StaticCollisionShape {
    let reference: FormID
    let transform: float4x4
    let geometry: NIFCollisionGeometry
    let bounds: ModelBounds

    var triangleCount: Int {
        guard case let .triangleSoup(_, indices) = geometry else { return 0 }
        return indices.count / 3
    }
}

nonisolated struct StaticCollisionStats: Equatable {
    var modelReferenceCount = 0
    var collisionModelReferenceCount = 0
    var bodyCount = 0
    var filteredBodyCount = 0
    var shapeCount = 0
    var triangleCount = 0
    var unsupportedReachableBlockCount = 0
    var decodeFailureCount = 0
    var loadFailureCount = 0
    var estimatedBytes = 0

    mutating func add(_ other: StaticCollisionStats) {
        modelReferenceCount += other.modelReferenceCount
        collisionModelReferenceCount += other.collisionModelReferenceCount
        bodyCount += other.bodyCount
        filteredBodyCount += other.filteredBodyCount
        shapeCount += other.shapeCount
        triangleCount += other.triangleCount
        unsupportedReachableBlockCount += other.unsupportedReachableBlockCount
        decodeFailureCount += other.decodeFailureCount
        loadFailureCount += other.loadFailureCount
        estimatedBytes += other.estimatedBytes
    }
}

nonisolated struct StaticCollisionSet {
    let location: CellSceneLocation?
    let shapes: [StaticCollisionShape]
    let stats: StaticCollisionStats
    var buildDurationMS: Double
    private let index: StaticCollisionSpatialIndex

    init(
        location: CellSceneLocation?,
        shapes: [StaticCollisionShape],
        stats: StaticCollisionStats,
        buildDurationMS: Double = 0
    ) {
        self.location = location
        self.shapes = shapes
        self.stats = stats
        self.buildDurationMS = buildDurationMS
        index = StaticCollisionSpatialIndex(shapes: shapes)
    }

    static let empty = StaticCollisionSet(
        location: nil,
        shapes: [],
        stats: StaticCollisionStats()
    )

    var indexNodeCount: Int {
        index.nodeCount
    }

    func candidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape] {
        index.query(overlapping: bounds)
            .map { shapes[$0] }
            .filter { $0.bounds.overlaps(bounds) }
    }
}

nonisolated private struct StaticCollisionSpatialIndex {
    private struct Node {
        let bounds: ModelBounds
        let left: Int?
        let right: Int?
        let shapeIndices: [Int]
    }

    private var nodes: [Node] = []
    private let root: Int?

    init(shapes: [StaticCollisionShape]) {
        var builder = Builder(shapes: shapes)
        root = builder.build(Array(shapes.indices))
        nodes = builder.nodes
    }

    var nodeCount: Int {
        nodes.count
    }

    func query(overlapping bounds: ModelBounds) -> [Int] {
        guard let root else { return [] }
        var result: [Int] = []
        var stack = [root]
        while let index = stack.popLast() {
            let node = nodes[index]
            guard node.bounds.overlaps(bounds) else { continue }
            result.append(contentsOf: node.shapeIndices)
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
        let shapes: [StaticCollisionShape]
        var nodes: [Node] = []

        mutating func build(_ indices: [Int]) -> Int? {
            guard let first = indices.first else { return nil }
            let bounds = indices.dropFirst().reduce(shapes[first].bounds) {
                $0.union(shapes[$1].bounds)
            }
            if indices.count <= 4 {
                nodes.append(Node(
                    bounds: bounds,
                    left: nil,
                    right: nil,
                    shapeIndices: indices.sorted()
                ))
                return nodes.count - 1
            }

            let extent = bounds.max - bounds.min
            let axis = extent.x >= extent.y && extent.x >= extent.z ? 0
                : (extent.y >= extent.z ? 1 : 2)
            let sorted = indices.sorted {
                centroid(of: shapes[$0].bounds, axis: axis)
                    < centroid(of: shapes[$1].bounds, axis: axis)
            }
            let midpoint = sorted.count / 2
            let placeholder = nodes.count
            nodes.append(Node(bounds: bounds, left: nil, right: nil, shapeIndices: []))
            let left = build(Array(sorted[..<midpoint]))
            let right = build(Array(sorted[midpoint...]))
            nodes[placeholder] = Node(
                bounds: bounds,
                left: left,
                right: right,
                shapeIndices: []
            )
            return placeholder
        }

        private func centroid(of bounds: ModelBounds, axis: Int) -> Float {
            (bounds.min[axis] + bounds.max[axis]) * 0.5
        }
    }
}

nonisolated extension ModelBounds {
    func overlaps(_ other: ModelBounds) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x
            && min.y <= other.max.y && max.y >= other.min.y
            && min.z <= other.max.z && max.z >= other.min.z
    }
}
