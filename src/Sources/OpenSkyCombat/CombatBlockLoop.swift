// The block loop's state and its start and stop rules, as pure values: when a guard may
// go up, how long it holds, and when it may drop. See docs/engine/combat-blocking.md.

import Foundation
import OpenSkyCombatInterface
import simd

/// What the block loop reads about the target this step.
nonisolated struct CombatTargetActions: Equatable, Sendable {
    enum Attack: Equatable, Sendable {
        case none
        /// Attack state 1: the swing winds up.
        case draw
        case swing
    }

    var attack = Attack.none
    var isPowerAttack = false
    var isBlocking = false
    var isRecoiling = false
    /// It holds a melee weapon or nothing; a bow or a spell does not count.
    var fightsInMelee = true
    /// Its weapon reach and its radius, both scaled.
    var reach: Float = 0
    var radius: Float = 0
    /// The strike angle of its attack, in degrees.
    var strikeAngleDegrees: Float = 35

    /// The default 35 degree hit cone of an attack without attack data.
    static let hitConeDegrees: Float = 35
}

nonisolated struct CombatBlockLoop: Equatable, Sendable {
    enum GuardKind: String, Equatable, Sendable {
        case block
        case blockAttack
    }

    /// A raised guard. It keeps its own clock, because a bash from the guard leaves the
    /// blocking phase and comes back to it.
    struct Guard: Equatable, Sendable {
        var kind: GuardKind
        var holdSeconds: Float
        var elapsed: Float = 0
        var nextBashRoll: Float
        var nextStopCheck: Float = 0
        var isFar = false
    }

    /// Seconds until the next pass.
    var untilPass: Float = 0
    var raised: Guard?
    /// The attack under way is a bash.
    var isBashing = false
    private(set) var guardCount = 0
    private(set) var bashCount = 0

    mutating func tick(_ seconds: Float) {
        untilPass -= seconds
        raised?.elapsed += seconds
    }

    mutating func raise(_ kind: GuardKind, holdSeconds: Float, settings: CombatBlockLoopSettings) {
        raised = Guard(kind: kind, holdSeconds: holdSeconds, nextBashRoll: settings.passSeconds)
        guardCount += 1
    }

    mutating func startBash() {
        isBashing = true
        bashCount += 1
    }

    /// The bash pick found no attack, so no bash started.
    mutating func cancelBash() {
        guard isBashing else { return }
        isBashing = false
        bashCount -= 1
    }
}

/// The geometry the loop's rules test.
nonisolated struct CombatBlockRules {
    let settings: CombatBlockLoopSettings
    let inputs: CombatBehaviorInputs

    private var target: CombatTargetActions {
        inputs.target
    }

    private var radii: Float {
        inputs.actorRadius + target.radius
    }

    /// The planar distance predicted `predictSeconds` ahead, from the target's velocity.
    var predictedDistance: Float {
        let ahead = inputs.targetPosition + inputs.targetVelocity * settings.predictSeconds
        let offset = ahead - inputs.actorPosition
        return simd_length(SIMD2(offset.x, offset.y))
    }

    /// The target draws or swings with the actor inside its strike angle times the mult.
    var targetAttacksActor: Bool {
        target.attack != .none
            && actorInsideTargetCone(degrees: target.strikeAngleDegrees * settings.strikeAngleMult)
    }

    var mayStartBlock: Bool {
        guard
            inputs.canBlock, !target.isBlocking, target.fightsInMelee,
            actorInsideTargetCone(degrees: CombatTargetActions.hitConeDegrees)
        else {
            return false
        }
        return retreatSpeed <= settings.targetRetreatSpeed
            && predictedDistance <= settings.blockStartDistance + radii + target.reach
    }

    var mayStartBlockAttack: Bool {
        guard inputs.canBash, target.attack == .draw, targetAttacksActor else { return false }
        let limit = radii + settings.blockAttackReachMult * target.reach
        return inputs.distance < limit || predictedDistance < limit
    }

    var isPastStopDistance: Bool {
        predictedDistance > settings.blockStopDistance + radii + target.reach
    }

    /// The bash chance's factor for the target's state.
    var bashTargetMult: Float {
        let mults = settings.bashTargetMults
        if target.isRecoiling {
            return mults.recoil
        }
        if target.attack != .none {
            return target.isPowerAttack ? mults.powerAttack : mults.attack
        }
        if
            target.isBlocking,
            actorInsideTargetCone(degrees: CombatTargetActions.hitConeDegrees)
        {
            return mults.blocking
        }
        return 1
    }

    /// How fast the target moves away from the actor, in units a second.
    private var retreatSpeed: Float {
        let offset = inputs.targetPosition - inputs.actorPosition
        let planar = SIMD2(offset.x, offset.y)
        let length = simd_length(planar)
        guard length > 1e-3 else { return 0 }
        return simd_dot(SIMD2(inputs.targetVelocity.x, inputs.targetVelocity.y), planar / length)
    }

    /// Whether the actor stands within `degrees` of the target's facing. An unknown facing
    /// counts as facing the actor.
    private func actorInsideTargetCone(degrees: Float) -> Bool {
        guard let yaw = inputs.targetYaw else { return true }
        let offset = inputs.actorPosition - inputs.targetPosition
        guard simd_length_squared(SIMD2(offset.x, offset.y)) > 1e-6 else { return true }
        let bearing = atan2f(offset.y, offset.x)
        return abs(remainder(bearing - yaw, 2 * .pi)) <= degrees * .pi / 180
    }
}
