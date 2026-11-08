import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyPhysics
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
    /// Carrying the player, who steers it.
    case ridden
    /// Sliding from a push until it fades.
    case knockedBack
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

    public init(
        actor: ReferenceKey,
        state: NPCMovementState,
        feetPosition: SIMD3<Float>,
        yaw: Float,
        waypointIndex: Int,
        waypointCount: Int,
        gait: LocomotionGait,
        repathCount: Int
    ) {
        self.actor = actor
        self.state = state
        self.feetPosition = feetPosition
        self.yaw = yaw
        self.waypointIndex = waypointIndex
        self.waypointCount = waypointCount
        self.gait = gait
        self.repathCount = repathCount
    }
}

/// What the movement authority publishes to animation and combat. A drive may
/// run a behavior graph or select in-place gait clips; neither can write the
/// capsule pose through this value.
nonisolated public struct NPCLocomotionDriveUpdate: Equatable, Sendable {
    public let actor: ReferenceKey
    public let intent: LocomotionIntent
    public let gait: LocomotionGait
    /// The MATT under the mover's feet, so its steps sound like the ground. Nil when unknown.
    public var groundMaterial: FormID?

    public init(
        actor: ReferenceKey,
        intent: LocomotionIntent,
        gait: LocomotionGait,
        groundMaterial: FormID? = nil
    ) {
        self.actor = actor
        self.intent = intent
        self.gait = gait
        self.groundMaterial = groundMaterial
    }
}
