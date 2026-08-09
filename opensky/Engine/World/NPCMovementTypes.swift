// Public values and the control seam for graph-agnostic NPC locomotion
// (issue #423). The path follower owns travel; animation and combat consume
// the same intent without becoming movement authorities.

import simd

nonisolated enum NPCMovementState: String, Equatable, Sendable {
    case moving
    case awaitingRepath
    case arrived
    case gaveUp
    /// Stopped on request before reaching the target, which is what an actor
    /// that came into weapon range or gave up a chase does (issue #424).
    case halted
}

nonisolated enum NPCMovementSettleReason: String, Equatable, Sendable {
    case arrival
    case giveUp
    case halt
    case cellHandoff
    case save
}

nonisolated struct NPCMovementReadout: Equatable, Sendable {
    let actor: ReferenceKey
    let state: NPCMovementState
    let feetPosition: SIMD3<Float>
    let yaw: Float
    let waypointIndex: Int
    let waypointCount: Int
    let gait: LocomotionGait
    let repathCount: Int
}

/// What the movement authority publishes to animation and combat. A drive may
/// run a behavior graph or select in-place gait clips; neither can write the
/// capsule pose through this value.
nonisolated struct NPCLocomotionDriveUpdate: Equatable, Sendable {
    let actor: ReferenceKey
    let intent: LocomotionIntent
    let gait: LocomotionGait
    let yaw: Float
    let deltaTime: Float
}

nonisolated struct NPCMovementPersistence: Equatable, Sendable {
    let actor: ReferenceKey
    let transform: ReferenceTransformOverride
    let cell: CellSceneLocation?
    let reason: NPCMovementSettleReason
}

nonisolated enum NPCMoveCommandResult: Equatable, Sendable {
    case started
    case actorNotResident
    case noPath(NavigationPathMiss)
    case moverCapReached
}

/// The panel and future AI-package seam. Item 16.8 can select an actor and a
/// picked point without knowing how paths, fixed steps, or persistence work.
protocol MoveToPointControl: AnyObject {
    @discardableResult
    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult

    /// Stops one actor where it stands (issue #424). Combat's "hold": reaching
    /// weapon range, raising a guard and giving up a chase all end in an actor
    /// that should stop walking through the movement authority rather than by
    /// having its last request quietly expire.
    ///
    /// - Returns: true when there was a live mover to stop.
    @discardableResult
    func stopActor(_ actor: ReferenceKey) -> Bool

    func npcMovementReadouts() -> [NPCMovementReadout]
}
