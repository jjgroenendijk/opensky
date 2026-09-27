// Turning one actor in place to face a point (issue #427, roadmap item 17.4).
//
// A conversation needs the speaker to look at the player, and the only thing in
// this engine that owns an actor's yaw is the movement authority
// (`NPCMovementRuntime`). Writing the yaw from the dialogue layer instead would
// give an actor two owners of its facing, and the frame after a package
// restarted a walk the two would disagree. So a turn is a request to that
// authority, exactly as a walk is, and it takes the actor's mover away for the
// same reason a walk takes the previous walk away.
//
// The turn is bounded by `NPCMovementRuntime.maximumYawSpeed`, the same rate a
// mover turns corners at, so an actor spun to face the player rotates at the
// speed the rest of its locomotion rotates at rather than snapping.
//
// Head tracking, eye contact and look-at IK are explicitly not this: the whole
// actor turns on the spot, its feet do not move, and nothing above the neck is
// aimed at anything (issue #427, "Out of scope").

import simd

/// What starting a turn needs. The placement and scale come from the caller
/// because an actor that has never moved has no entry in the movement runtime
/// at all, and the authored ACHR placement is then the only record of where it
/// is standing.
nonisolated struct NPCFaceStart: Equatable, Sendable {
    let actor: ReferenceKey
    let formID: FormID
    /// Where the actor is standing and how it was authored to be rotated.
    let placement: PlacedReference.Placement
    let scale: Float
    /// The world point to turn towards. Only its horizontal bearing is used —
    /// an actor turns about world +Z and never leans.
    let target: SIMD3<Float>
}

/// One actor turning on the spot. Deliberately not a `NPCMover` with an empty
/// path: a mover owns a `WalkController`, a path, a stuck timer and a repath
/// budget, none of which mean anything to an actor that is not going anywhere.
nonisolated struct NPCFacingHold: Equatable, Sendable {
    let actor: ReferenceKey
    let formID: FormID
    let authoredPlacement: PlacedReference.Placement
    let scale: Float
    /// Where the actor stands. Fixed for the life of the hold — this is a turn,
    /// not a move.
    let feetPosition: SIMD3<Float>
    /// The bearing being turned towards.
    private(set) var targetYaw: Float
    private(set) var yaw: Float

    init(start: NPCFaceStart, feetPosition: SIMD3<Float>, yaw: Float) {
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
    var isSettled: Bool {
        abs(NPCYawMath.shortestTurn(from: yaw, to: targetYaw)) <= Self.settleTolerance
    }

    /// Re-aims a hold that is already running, so a player who walks around a
    /// speaker mid-conversation is followed rather than left behind.
    mutating func aim(at target: SIMD3<Float>) {
        targetYaw = Self.bearing(from: feetPosition, to: target, fallback: targetYaw)
    }

    /// Turns by one frame and reports the drive the animation layer plays.
    ///
    /// The drive is published every frame, settled or not, because a still
    /// actor still has to be told it is still: that is what returns it to its
    /// idle clip after a walk.
    mutating func advance(by frameTime: Float) -> NPCLocomotionDriveUpdate {
        yaw = NPCYawMath.turn(
            from: yaw,
            to: targetYaw,
            maximum: NPCMovementRuntime.maximumYawSpeed * max(frameTime, 0)
        )
        return NPCLocomotionDriveUpdate(
            actor: actor,
            intent: .still,
            gait: .walk,
            yaw: yaw,
            deltaTime: frameTime
        )
    }

    var transform: ReferenceTransformOverride {
        ReferenceTransformOverride(
            position: feetPosition,
            rotation: SIMD3(authoredPlacement.rotation.x, authoredPlacement.rotation.y, yaw),
            scale: scale
        )
    }

    /// The same projection `NPCMover` publishes, so a turning actor and a
    /// walking one reach the draw path identically.
    var instanceDelta: float4x4 {
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

    var readout: NPCMovementReadout {
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

    func persistence(reason: NPCMovementSettleReason) -> NPCMovementPersistence {
        NPCMovementPersistence(actor: actor, transform: transform, cell: nil, reason: reason)
    }

    static let settleTolerance = MatrixMath.radians(fromDegrees: 0.5)

    /// The yaw that points from `origin` at `target`, or `fallback` when the
    /// two are the same column of air.
    static func bearing(
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
nonisolated enum NPCYawMath {
    /// The signed turn from one bearing to another, taking the short way round.
    static func shortestTurn(from source: Float, to target: Float) -> Float {
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
    static func turn(from source: Float, to target: Float, maximum: Float) -> Float {
        let delta = shortestTurn(from: source, to: target)
        return source + min(max(delta, -maximum), maximum)
    }
}
