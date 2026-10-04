// Public values and the control seam for graph-agnostic NPC locomotion.
// The path follower owns travel; animation and combat consume
// the same intent without becoming movement authorities.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyWorldState
import simd

nonisolated public enum NPCMovementState: String, Equatable, Sendable {
    case moving
    case awaitingRepath
    case arrived
    case gaveUp
    /// Stopped on request before reaching the target, which is what an actor
    /// that came into weapon range or gave up a chase does.
    case halted
    /// Turning on the spot towards a point, feet planted.
    case turning
    /// Turned, and holding that bearing until the hold is released.
    case facing
}

nonisolated public enum NPCMovementSettleReason: String, Equatable, Sendable {
    case arrival
    case giveUp
    case halt
    case cellHandoff
    case save
    /// An in-place turn reached the bearing it was asked for.
    case turn
}

nonisolated public struct NPCMovementReadout: Equatable, Sendable {
    public let actor: ReferenceKey
    public let state: NPCMovementState
    public let feetPosition: SIMD3<Float>
    public let yaw: Float
    public let waypointIndex: Int
    public let waypointCount: Int
    public let gait: LocomotionGait
    public let repathCount: Int
}

/// What the movement authority publishes to animation and combat. A drive may
/// run a behavior graph or select in-place gait clips; neither can write the
/// capsule pose through this value.
nonisolated public struct NPCLocomotionDriveUpdate: Equatable, Sendable {
    public let actor: ReferenceKey
    public let intent: LocomotionIntent
    public let gait: LocomotionGait
}

/// The rigid move from where the cell build drew an actor to where it stands now.
/// The renderer applies it to the actor's baked instance, so nothing rebuilds.
nonisolated public enum NPCDrawDelta {
    public static func from(
        drawn: PlacedReference.Placement,
        to current: ReferenceTransformOverride,
        scale: Float
    ) -> float4x4 {
        let built = MatrixMath.placement(
            position: drawn.position, rotation: drawn.rotation, scale: scale
        )
        let live = MatrixMath.placement(
            position: current.position, rotation: current.rotation, scale: scale
        )
        return live * built.inverse
    }
}

nonisolated public struct NPCMovementPersistence: Equatable, Sendable {
    public let actor: ReferenceKey
    public let transform: ReferenceTransformOverride
    public let cell: CellSceneLocation?
    public let reason: NPCMovementSettleReason
}

nonisolated public enum NPCMoveCommandResult: Equatable, Sendable {
    case started
    case actorNotResident
    case noPath(NavigationPathMiss)
    case moverCapReached
}
