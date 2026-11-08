// Value types shared by the navmesh graph, the path query API and the path follower.
// Coordinates are world units; path endpoints are feet positions.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
public import OpenSkyWorldInterface
import simd

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

nonisolated extension NavigationPath {
    /// One leg to `point` with no corridor, so no cell rebuild invalidates it.
    /// A path through `points` in order, with no navmesh under it.
    public static func through(_ points: [SIMD3<Float>]) -> NavigationPath {
        NavigationPath(
            waypoints: points, doorCrossings: [],
            stats: NavigationPathStats(nodesExpanded: 0, corridorTriangleCount: 0),
            corridor: [], cellSequences: [:], target: points.last ?? .zero
        )
    }

    public static func straight(to point: SIMD3<Float>) -> NavigationPath {
        NavigationPath(
            waypoints: [point], doorCrossings: [],
            stats: NavigationPathStats(nodesExpanded: 0, corridorTriangleCount: 0),
            corridor: [], cellSequences: [:], target: point
        )
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

    public init(identifier: UInt64, result: NavigationPathResult) {
        self.identifier = identifier
        self.result = result
    }
}
