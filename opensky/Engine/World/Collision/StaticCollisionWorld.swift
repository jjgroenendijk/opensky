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
    /// The MATT material type this surface is made of (issue #358), already
    /// resolved from the NIF's Havok material value at build time so that
    /// nothing downstream has to know a mesh names its surface by hash. Nil
    /// where the mesh carries no material or names one no MATT hashes to.
    let material: FormID?

    init(
        reference: FormID,
        transform: float4x4,
        geometry: NIFCollisionGeometry,
        bounds: ModelBounds,
        material: FormID? = nil
    ) {
        self.reference = reference
        self.transform = transform
        self.geometry = geometry
        self.bounds = bounds
        self.material = material
    }

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
    private let index: BoundsSpatialIndex

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
        index = BoundsSpatialIndex(bounds: shapes.map(\.bounds))
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

nonisolated extension ModelBounds {
    func overlaps(_ other: ModelBounds) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x
            && min.y <= other.max.y && max.y >= other.min.y
            && min.z <= other.max.z && max.z >= other.min.z
    }
}
