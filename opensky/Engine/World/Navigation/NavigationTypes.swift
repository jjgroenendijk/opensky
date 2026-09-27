// Value types shared by the streamed navmesh graph, path query API and the
// future actor path follower (issue #200). Navigation coordinates are world
// engine units and path endpoints are feet positions.

import simd

nonisolated struct NavigationTriangleID: Hashable, Comparable, Sendable {
    let navmesh: FormID
    let triangle: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.navmesh.rawValue, lhs.triangle) < (rhs.navmesh.rawValue, rhs.triangle)
    }
}

nonisolated struct NavigationProjection: Equatable, Sendable {
    let triangle: NavigationTriangleID
    /// Closest point on the triangle, including height from its plane.
    let position: SIMD3<Float>
    let distance: Float
}

nonisolated enum NavigationProjectionResult: Equatable, Sendable {
    case hit(NavigationProjection)
    case miss
}

nonisolated struct NavigationDoorCrossing: Equatable, Sendable {
    let door: FormID
    /// Index into `NavigationPath.waypoints` at which the door is used.
    let waypointIndex: Int
}

nonisolated struct NavigationPathStats: Equatable, Sendable {
    let nodesExpanded: Int
    let corridorTriangleCount: Int
}

nonisolated struct NavigationPath: Equatable, Sendable {
    let waypoints: [SIMD3<Float>]
    let doorCrossings: [NavigationDoorCrossing]
    let stats: NavigationPathStats

    /// Kept with the result so unload/rebuild invalidation is exact rather
    /// than tied to a global graph generation.
    let corridor: [NavigationTriangleID]
    let cellSequences: [CellSceneLocation: UInt64]
    let target: SIMD3<Float>
}

nonisolated enum NavigationPathMiss: Equatable, Sendable {
    case startProjection
    case targetProjection
    case disconnected
}

nonisolated enum NavigationPathResult: Equatable, Sendable {
    case path(NavigationPath)
    case miss(NavigationPathMiss)
}

nonisolated struct NavigationPathQuery: Equatable, Sendable {
    /// Default bounded projection radius in engine units.
    static let defaultProjectionRadius: Float = 256
    /// A tracked target must move this far before its path needs rebuilding.
    static let defaultTargetMoveTolerance: Float = 64

    let start: SIMD3<Float>
    let target: SIMD3<Float>
    let capsuleRadius: Float
    let projectionRadius: Float

    init(
        start: SIMD3<Float>,
        target: SIMD3<Float>,
        capsuleRadius: Float = PlayerCapsule.standard.radius,
        projectionRadius: Float = Self.defaultProjectionRadius
    ) {
        self.start = start
        self.target = target
        self.capsuleRadius = max(0, capsuleRadius)
        self.projectionRadius = max(0, projectionRadius)
    }
}

/// One future follower's request for a budgeted path refresh.
nonisolated struct NavigationRepathRequest: Equatable, Sendable {
    let identifier: UInt64
    let query: NavigationPathQuery
}

nonisolated struct NavigationRepathResponse: Equatable, Sendable {
    let identifier: UInt64
    let result: NavigationPathResult
}
