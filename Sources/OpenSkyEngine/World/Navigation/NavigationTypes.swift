// Value types shared by the streamed navmesh graph, path query API and the
// future actor path follower (issue #200). Navigation coordinates are world
// engine units and path endpoints are feet positions.

import OpenSkyFormatsESM
import simd

nonisolated public struct NavigationTriangleID: Hashable, Comparable, Sendable {
    public let navmesh: FormID
    public let triangle: Int

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.navmesh.rawValue, lhs.triangle) < (rhs.navmesh.rawValue, rhs.triangle)
    }
}

nonisolated public struct NavigationProjection: Equatable, Sendable {
    public let triangle: NavigationTriangleID
    /// Closest point on the triangle, including height from its plane.
    public let position: SIMD3<Float>
    public let distance: Float
}

nonisolated public enum NavigationProjectionResult: Equatable, Sendable {
    case hit(NavigationProjection)
    case miss
}

nonisolated public struct NavigationDoorCrossing: Equatable, Sendable {
    public let door: FormID
    /// Index into `NavigationPath.waypoints` at which the door is used.
    public let waypointIndex: Int
}

nonisolated public struct NavigationPathStats: Equatable, Sendable {
    public let nodesExpanded: Int
    public let corridorTriangleCount: Int
}

nonisolated public struct NavigationPath: Equatable, Sendable {
    public let waypoints: [SIMD3<Float>]
    public let doorCrossings: [NavigationDoorCrossing]
    public let stats: NavigationPathStats

    /// Kept with the result so unload/rebuild invalidation is exact rather
    /// than tied to a global graph generation.
    public let corridor: [NavigationTriangleID]
    public let cellSequences: [CellSceneLocation: UInt64]
    public let target: SIMD3<Float>
}

nonisolated public enum NavigationPathMiss: Equatable, Sendable {
    case startProjection
    case targetProjection
    case disconnected
}

nonisolated public enum NavigationPathResult: Equatable, Sendable {
    case path(NavigationPath)
    case miss(NavigationPathMiss)
}

nonisolated public struct NavigationPathQuery: Equatable, Sendable {
    /// Default bounded projection radius in engine units.
    public static let defaultProjectionRadius: Float = 256
    /// A tracked target must move this far before its path needs rebuilding.
    public static let defaultTargetMoveTolerance: Float = 64

    public let start: SIMD3<Float>
    public let target: SIMD3<Float>
    public let capsuleRadius: Float
    public let projectionRadius: Float

    public init(
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
nonisolated public struct NavigationRepathRequest: Equatable, Sendable {
    public let identifier: UInt64
    public let query: NavigationPathQuery
}

nonisolated public struct NavigationRepathResponse: Equatable, Sendable {
    public let identifier: UInt64
    public let result: NavigationPathResult
}
