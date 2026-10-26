// The pure rules of riding: who the player may mount, how a mount steers, and what a
// rider may not do. `MountCoordinator` is the shell. See docs/engine/riding.md.

import Foundation
import OpenSkyRendering
import simd

/// What kind of actor a mount is. It picks the graph events of the mount and dismount.
nonisolated public enum MountKind: String, Equatable, Sendable {
    case horse
    case dragon

    public var events: MountGraphEvents {
        self == .horse ? .horse : .dragon
    }
}

/// Who owns a mount, as the crime rules see it.
nonisolated public enum MountOwnership: Equatable, Sendable {
    /// No owner, or the player.
    case free
    /// Somebody else: riding it is a crime.
    case other
}

/// What the world says about one actor the player wants to mount.
nonisolated public struct MountCandidate: Equatable, Sendable {
    public var isDead = false
    /// The saddle bone the skeleton has, or nil when it has none.
    public var saddleBone: String?
    /// The race carries `ActorTypeDragon`.
    public var isDragon = false
    /// The result of the player's Allow Mount Actor entry points with this actor as
    /// the target, starting from 0.
    public var allowMountActor: Float = 0
    /// Another actor already sits on it.
    public var isRidden = false
    public var ownership = MountOwnership.free

    public init() {}
}

nonisolated public enum MountRefusal: String, Equatable, Sendable {
    case alreadyRiding = "the player already rides"
    case dead = "it is dead"
    case noSaddle = "its skeleton has no saddle bone"
    case needsPerk = "Allow Mount Actor does not pass for it"
    case ridden = "somebody rides it"
    case notLoaded = "it is not loaded"
}

nonisolated public enum MountDecision: Equatable, Sendable {
    /// Mount it. `steals` is true when riding it is a crime.
    case mount(MountKind, saddleBone: String, steals: Bool)
    case refuse(MountRefusal)
}

/// How far a mount turns and how much it moves forward in one step.
nonisolated public struct MountSteer: Equatable, Sendable {
    /// Walk yaw, counter-clockwise from +X.
    public var heading: Float
    /// 0 stands still, 1 is full forward input.
    public var throttle: Float
}

nonisolated public enum MountRules: Sendable {
    /// How long a mount or a dismount may wait for the rider's graph before it
    /// completes anyway. Longer than the paired clips (1.67 s and 2.13 s).
    public static let phaseTimeout: Float = 4

    /// A dragon needs Allow Mount Actor to pass. Any other actor with a saddle bone
    /// is a horse. See docs/engine/riding.md for why this is OpenSky's reading.
    public static func decide(_ candidate: MountCandidate?, isRiding: Bool) -> MountDecision {
        guard !isRiding else { return .refuse(.alreadyRiding) }
        guard let candidate else { return .refuse(.notLoaded) }
        guard !candidate.isDead else { return .refuse(.dead) }
        guard let saddle = candidate.saddleBone else { return .refuse(.noSaddle) }
        guard !candidate.isRidden else { return .refuse(.ridden) }
        if candidate.isDragon {
            guard candidate.allowMountActor != 0 else { return .refuse(.needsPerk) }
            return .mount(.dragon, saddleBone: saddle, steals: false)
        }
        return .mount(.horse, saddleBone: saddle, steals: candidate.ownership == .other)
    }

    /// Turns `heading` toward the direction the player pushes, seen from the camera, by
    /// at most `turnRate` radians per second. A ridden mount cannot back up: pushing
    /// back turns it around while it moves.
    public static func steer(
        heading: Float, forward: Float, right: Float, cameraYaw: Float, deltaTime: Float,
        turnRate: Float = MountSettings.vanilla.turnRate
    ) -> MountSteer {
        let push = SIMD2(forward, right)
        let amount = min(simd_length(push), 1)
        guard amount > 0.001, deltaTime > 0 else {
            return MountSteer(heading: heading, throttle: 0)
        }
        let ahead = SIMD2(cos(cameraYaw), sin(cameraYaw))
        let side = SIMD2(sin(cameraYaw), -cos(cameraYaw))
        let wanted = ahead * forward + side * right
        let target = atan2(wanted.y, wanted.x)
        let turn = remainder(target - heading, 2 * Float.pi)
        let limit = turnRate * deltaTime
        let next = heading + min(max(turn, -limit), limit)
        return MountSteer(heading: remainder(next, 2 * Float.pi), throttle: amount)
    }

    /// The input a rider keeps. On horseback the game allows melee weapons, bows, and
    /// crossbows in the right hand, and blocks sneaking, blocking, magic, shouts,
    /// unarmed attacks, and staves (UESP "Skyrim:Combat", Horse-Mounted Combat). A dragon
    /// rider shouts and casts readied spells (UESP "Skyrim:Dragon Riding"). Jump and
    /// sneak go to the mount.
    public static func riderInput(
        _ input: CameraInput, rightHandType: Int32, kind: MountKind = .horse
    ) -> CameraInput {
        var kept = input
        kept.sneak = false
        kept.block = false
        kept.jump = false
        kept.shout = kind == .dragon && input.shout
        let attacks = kind == .dragon
            ? rightHandType == readiedSpell : isMountedWeapon(rightHandType)
        if !attacks {
            kept.attack = false
            kept.attackHeld = false
        }
        return kept
    }

    /// `iRightHandType` of a readied spell, the one thing a dragon rider casts by hand.
    public static let readiedSpell: Int32 = 9

    /// Where a rider stands after a dismount, from the mount's feet: the race's
    /// dismount offset turned into the world, x to the mount's right, y forward.
    public static func dismountPosition(offset: SIMD3<Float>, yaw: Float) -> SIMD2<Float> {
        let forward = SIMD2(cos(yaw), sin(yaw))
        let right = SIMD2(sin(yaw), -cos(yaw))
        return right * offset.x + forward * offset.y
    }

    /// One-handed and two-handed melee weapons, bows, and crossbows, in the
    /// `iRightHandType` encoding (docs/engine/combat-graph-names.md).
    public static func isMountedWeapon(_ rightHandType: Int32) -> Bool {
        (1 ... 7).contains(rightHandType) || rightHandType == 12
    }
}
