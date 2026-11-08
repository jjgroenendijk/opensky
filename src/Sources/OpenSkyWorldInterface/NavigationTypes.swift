public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyPhysics
import simd

nonisolated public struct NavigationTriangleID: Hashable, Comparable, Sendable {
    public let navmesh: FormID
    public let triangle: Int

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.navmesh.rawValue, lhs.triangle) < (rhs.navmesh.rawValue, rhs.triangle)
    }

    public init(
        navmesh: FormID,
        triangle: Int
    ) {
        self.navmesh = navmesh
        self.triangle = triangle
    }
}

nonisolated public struct NavigationDoorCrossing: Equatable, Sendable {
    public let door: FormID
    /// Index into `NavigationPath.waypoints` at which the door is used.
    public let waypointIndex: Int

    public init(
        door: FormID,
        waypointIndex: Int
    ) {
        self.door = door
        self.waypointIndex = waypointIndex
    }
}

/// A jump up or a drop down a navmesh ledge link. The mover jumps from the waypoint
/// at `waypointIndex` to the next one.
nonisolated public struct NavigationLedgeCrossing: Equatable, Sendable {
    public let waypointIndex: Int

    public init(
        waypointIndex: Int
    ) {
        self.waypointIndex = waypointIndex
    }
}

nonisolated public struct NavigationPathStats: Equatable, Sendable {
    public let nodesExpanded: Int
    public let corridorTriangleCount: Int

    public init(
        nodesExpanded: Int,
        corridorTriangleCount: Int
    ) {
        self.nodesExpanded = nodesExpanded
        self.corridorTriangleCount = corridorTriangleCount
    }
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
    public var ledgeCrossings: [NavigationLedgeCrossing] = []

    public init(
        waypoints: [SIMD3<Float>],
        doorCrossings: [NavigationDoorCrossing],
        stats: NavigationPathStats,
        corridor: [NavigationTriangleID],
        cellSequences: [CellSceneLocation: UInt64],
        target: SIMD3<Float>,
        ledgeCrossings: [NavigationLedgeCrossing] = []
    ) {
        self.waypoints = waypoints
        self.doorCrossings = doorCrossings
        self.stats = stats
        self.corridor = corridor
        self.cellSequences = cellSequences
        self.target = target
        self.ledgeCrossings = ledgeCrossings
    }
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

nonisolated public enum NPCMoveCommandResult: Equatable, Sendable {
    case started
    case actorNotResident
    case noPath(NavigationPathMiss)
    case moverCapReached
}
