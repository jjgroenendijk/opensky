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

/// One walk step of a mover, in world units: the move it asked for, what its long body
/// took off, and how far its feet moved.
nonisolated public struct NPCMoveStepReadout: Equatable, Sendable {
    public var wanted = SIMD2<Float>.zero
    public var bodyCorrection = SIMD2<Float>.zero
    public var moved = SIMD3<Float>.zero
    /// The speed the step planned, and the fixed steps the walk controller ran.
    public var speed: Float = 0
    public var steps = 0
    public var yaw: Float = 0
    /// The long body part that pushed back most in the last fixed step.
    public var bodyPush: LongBodyPush?

    public init(speed: Float = 0, yaw: Float = 0) {
        self.speed = speed
        self.yaw = yaw
    }

    /// Counts one fixed step that asked for `wanted`.
    public mutating func note(wanted: SIMD2<Float>) {
        self.wanted += wanted
        steps += 1
    }

    public mutating func note(_ push: LongBodyPush) {
        bodyCorrection += push.added
        bodyPush = push
    }

    public func moving(by moved: SIMD3<Float>) -> NPCMoveStepReadout {
        var step = self
        step.moved = moved
        return step
    }

    /// One line for the agent readout.
    public var text: String {
        var text = "wanted \(wanted) body \(bodyCorrection) moved \(moved)"
            + " speed \(speed) steps \(steps) yaw \(yaw)"
        if let part = bodyPush?.part, let resting = bodyPush?.resting {
            text += " part \(part) resting \(resting)"
        }
        return text
    }
}

/// How often one actor's walk was started, and stopped while it ran, since the load.
nonisolated public struct NPCMoveCommandCounts: Equatable, Sendable {
    public var starts = 0
    public var stops = 0

    public init() {}

    public var text: String {
        "starts \(starts) stops \(stops)"
    }
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
    /// The waypoint the mover walks to now, and the end of its path.
    public var nextWaypoint: SIMD3<Float>?
    public var target: SIMD3<Float>?
    public var lastStep: NPCMoveStepReadout?
    public var commands: NPCMoveCommandCounts?

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
