// Turning one actor in place to face a point. The movement authority
// (`NPCMovementRuntime`) owns an actor's yaw, so a turn is a request to it, like
// a walk. The turn rate is `NPCMovementRuntime.maximumYawSpeed`. The whole actor
// turns; there is no head tracking or look-at IK.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyWorldState
import simd

/// What starting a turn needs. The placement and scale come from the caller
/// because an actor that has never moved has no entry in the movement runtime
/// at all, and the authored ACHR placement is then the only record of where it
/// is standing.
nonisolated public struct NPCFaceStart: Equatable, Sendable {
    public let actor: ReferenceKey
    public let formID: FormID
    /// Where the actor is standing and how it was authored to be rotated.
    public let placement: PlacedReference.Placement
    public let scale: Float
    /// The world point to turn towards. Only its horizontal bearing is used —
    /// an actor turns about world +Z and never leans.
    public let target: SIMD3<Float>
}

/// One actor turning on the spot. Deliberately not a `NPCMover` with an empty
/// path: a mover owns a `WalkController`, a path, a stuck timer and a repath
/// budget, none of which mean anything to an actor that is not going anywhere.
nonisolated public struct NPCFacingHold: Equatable, Sendable {
    public let actor: ReferenceKey
    public let formID: FormID
    public let authoredPlacement: PlacedReference.Placement
    public let scale: Float
    /// Where the actor stands. Fixed for the life of the hold — this is a turn,
    /// not a move.
    public let feetPosition: SIMD3<Float>
    /// The bearing being turned towards.
    public private(set) var targetYaw: Float
    public private(set) var yaw: Float

    public init(start: NPCFaceStart, feetPosition: SIMD3<Float>, yaw: Float) {
        actor = start.actor
        formID = start.formID
        authoredPlacement = start.placement
        scale = start.scale
        self.feetPosition = feetPosition
        self.yaw = yaw
        targetYaw = Self.bearing(from: feetPosition, to: start.target, fallback: yaw)
    }

    /// True once the actor is pointing where it was asked to point, to within
    /// half a degree — below what a viewer can see and above what the fixed
    /// step's own arithmetic settles to.
    public var isSettled: Bool {
        abs(NPCYawMath.shortestTurn(from: yaw, to: targetYaw)) <= Self.settleTolerance
    }

    /// Re-aims a hold that is already running, so a player who walks around a
    /// speaker mid-conversation is followed rather than left behind.
    public mutating func aim(at target: SIMD3<Float>) {
        targetYaw = Self.bearing(from: feetPosition, to: target, fallback: targetYaw)
    }

    /// Turns by one frame and reports the drive the animation layer plays.
    ///
    /// The drive is published every frame, settled or not, because a still
    /// actor still has to be told it is still: that is what returns it to its
    /// idle clip after a walk.
    public mutating func advance(by frameTime: Float) -> NPCLocomotionDriveUpdate {
        yaw = NPCYawMath.turn(
            from: yaw,
            to: targetYaw,
            maximum: NPCMovementRuntime.maximumYawSpeed * max(frameTime, 0)
        )
        return NPCLocomotionDriveUpdate(
            actor: actor,
            intent: .still,
            gait: .walk
        )
    }

    public var transform: ReferenceTransformOverride {
        ReferenceTransformOverride(
            position: feetPosition,
            rotation: SIMD3(authoredPlacement.rotation.x, authoredPlacement.rotation.y, yaw),
            scale: scale
        )
    }

    /// The same projection `NPCMover` publishes, so a turning actor and a
    /// walking one reach the draw path identically.
    public var instanceDelta: float4x4 {
        let authored = MatrixMath.placement(
            position: authoredPlacement.position,
            rotation: authoredPlacement.rotation,
            scale: scale
        )
        let current = MatrixMath.placement(
            position: transform.position,
            rotation: transform.rotation,
            scale: scale
        )
        return current * authored.inverse
    }

    public var readout: NPCMovementReadout {
        NPCMovementReadout(
            actor: actor,
            state: isSettled ? .facing : .turning,
            feetPosition: feetPosition,
            yaw: yaw,
            waypointIndex: 0,
            waypointCount: 0,
            gait: .walk,
            repathCount: 0
        )
    }

    public func persistence(reason: NPCMovementSettleReason) -> NPCMovementPersistence {
        NPCMovementPersistence(actor: actor, transform: transform, cell: nil, reason: reason)
    }

    public static let settleTolerance = MatrixMath.radians(fromDegrees: 0.5)

    /// The yaw that points from `origin` at `target`, or `fallback` when the
    /// two are the same column of air.
    public static func bearing(
        from origin: SIMD3<Float>,
        to target: SIMD3<Float>,
        fallback: Float
    ) -> Float {
        let delta = SIMD2(target.x - origin.x, target.y - origin.y)
        guard simd_length(delta) > .ulpOfOne else { return fallback }
        return atan2f(delta.y, delta.x)
    }
}

/// The bounded-turn arithmetic a mover corners with and a facing hold turns
/// with. One home, because two copies of an angle wrap is how a walking actor
/// and a turning one end up disagreeing about which way round is shorter.
nonisolated public enum NPCYawMath: Sendable {
    /// The signed turn from one bearing to another, taking the short way round.
    public static func shortestTurn(from source: Float, to target: Float) -> Float {
        var delta = (target - source).truncatingRemainder(dividingBy: .pi * 2)
        if delta > .pi {
            delta -= .pi * 2
        }
        if delta < -.pi {
            delta += .pi * 2
        }
        return delta
    }

    /// The same turn, clamped to what one step is allowed to rotate by.
    public static func turn(from source: Float, to target: Float, maximum: Float) -> Float {
        let delta = shortestTurn(from: source, to: target)
        return source + min(max(delta, -maximum), maximum)
    }
}
