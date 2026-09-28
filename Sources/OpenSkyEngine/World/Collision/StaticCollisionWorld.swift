// Immutable per-cell static collision world (milestone 4.3). NIF geometry is
// placed in world space through REFR x body x shape transforms, then indexed
// by a small AABB BVH. Streaming owns the resulting value beside CellScene;
// removing the cell releases its shapes + index together.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import simd

nonisolated public struct StaticCollisionShape: Sendable {
    public let reference: FormID
    public let transform: float4x4
    public let geometry: NIFCollisionGeometry
    public let bounds: ModelBounds
    /// The MATT material type this surface is made of (issue #358), already
    /// resolved from the NIF's Havok material value at build time so that
    /// nothing downstream has to know a mesh names its surface by hash. Nil
    /// where the mesh carries no material or names one no MATT hashes to.
    public let material: FormID?

    public init(
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

    public var triangleCount: Int {
        guard case let .triangleSoup(_, indices) = geometry else { return 0 }
        return indices.count / 3
    }
}

nonisolated public struct StaticCollisionStats: Equatable, Sendable {
    public var modelReferenceCount = 0
    public var collisionModelReferenceCount = 0
    public var bodyCount = 0
    public var filteredBodyCount = 0
    public var shapeCount = 0
    public var triangleCount = 0
    public var unsupportedReachableBlockCount = 0
    public var decodeFailureCount = 0
    public var loadFailureCount = 0
    public var estimatedBytes = 0

    public mutating func add(_ other: StaticCollisionStats) {
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

nonisolated public struct StaticCollisionSet: Sendable {
    public let location: CellSceneLocation?
    public let shapes: [StaticCollisionShape]
    public let stats: StaticCollisionStats
    public var buildDurationMS: Double
    private let index: BoundsSpatialIndex

    public init(
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

    public static let empty = StaticCollisionSet(
        location: nil,
        shapes: [],
        stats: StaticCollisionStats()
    )

    public var indexNodeCount: Int {
        index.nodeCount
    }

    public func candidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape] {
        index.query(overlapping: bounds)
            .map { shapes[$0] }
            .filter { $0.bounds.overlaps(bounds) }
    }
}

nonisolated extension ModelBounds {
    public func overlaps(_ other: ModelBounds) -> Bool {
        min.x <= other.max.x && max.x >= other.min.x
            && min.y <= other.max.y && max.y >= other.min.y
            && min.z <= other.max.z && max.z >= other.min.z
    }
}
