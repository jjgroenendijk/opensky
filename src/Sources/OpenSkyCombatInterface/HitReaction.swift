// Which reaction a hit gives its target: a large recoil, a stagger with its magnitude
// and direction, a block hit, and the attacker's recoil. docs/engine/hit-reactions.md.

import Foundation
public import OpenSkyActorsInterface
public import OpenSkyFormatsESM
import simd

/// What the stagger magnitude reads of the attack and of the target's state.
nonisolated public struct HitReactionFacts: Equatable, Sendable {
    /// The stagger value of the attack data behind the swing. Zero when it has none.
    public var attackStagger: Float = 0
    /// The attacker's `Block` and the target's `Mass`.
    public var attackerBlock: Float = 0
    public var targetMass: Float = 1
    public var targetRecoils = false
    public var targetRuns = false
    /// A target that is staggered already does not start a second stagger.
    public var targetStaggered = false
    /// The angle from the target's heading to the attacker, as a part of a full turn.
    public var direction: Float = 0

    public init() {}

    /// `staggerDirection`: 0 with no attacker, else 0 to 1 of a full clockwise turn.
    /// `targetFacing` is a yaw with `cos` on x and `sin` on y.
    public static func direction(
        targetFacing: Float, target: SIMD3<Float>, attacker: SIMD3<Float>?
    ) -> Float {
        guard let attacker, attacker != target else { return 0 }
        let bearing = atan2(attacker.y - target.y, attacker.x - target.x)
        let turn = (targetFacing - bearing) / (2 * .pi)
        let part = turn - turn.rounded(.down)
        return part.isFinite ? part : 0
    }
}

/// One hit, as the reaction rule reads it.
nonisolated public struct HitReactionHit: Equatable, Sendable {
    public var facts = HitReactionFacts()
    public var handType = CombatHandType.handToHand
    public var isBash = false
    public var bashesWithShield = false
    public var wasBlocked = false
    public var isPlayerTarget = false
    public var isMelee = true
    /// `Mod Target Stagger` times `Mod Incoming Stagger`.
    public var perkMultiplier: Float = 1

    public init() {}
}

nonisolated public struct HitReaction: Equatable, Sendable {
    /// The target performs Large Recoil. A bash never staggers.
    public var largeRecoil = false
    /// The magnitude written to `staggerMagnitude`, at most 1. Nil: no stagger.
    public var staggerMagnitude: Float?
    /// The target performs Block Hit.
    public var blockHit = false
    /// The attacker of a blocked melee hit performs Recoil.
    public var attackerRecoils = false

    public init() {}
}

/// One hit and the reaction it gave, for the readout.
nonisolated public struct HitReactionReport: Equatable, Sendable {
    public var attacker: ReferenceKey
    public var target: ReferenceKey
    public var hit: HitReactionHit
    public var reaction: HitReaction

    public init(
        attacker: ReferenceKey, target: ReferenceKey, hit: HitReactionHit, reaction: HitReaction
    ) {
        self.attacker = attacker
        self.target = target
        self.hit = hit
        self.reaction = reaction
    }
}

nonisolated public enum HitReactionRule {
    /// 1 for a shield or no weapon, 0.5 for a two-handed sword or axe, a bow, or a
    /// crossbow, and 0.2 for any other weapon.
    public static func weaponFactor(_ hit: HitReactionHit) -> Float {
        if hit.bashesWithShield {
            return 1
        }
        switch hit.handType {
        case .handToHand: return 1
        case .greatsword, .battleaxe, .bow, .crossbow: return 0.5
        default: return 0.2
        }
    }

    /// max(0, N / M × K × W × S), before the perks and the clamp to 1.
    public static func magnitude(_ hit: HitReactionHit) -> Float {
        let facts = hit.facts
        let skill = 0.5 + 0.01 * finite(facts.attackerBlock)
        var state: Float = hit.wasBlocked ? 0 : 1
        if facts.targetRecoils {
            state *= 1.5
        }
        if facts.targetRuns {
            state *= 1.5
        }
        let mass = facts.targetMass.isFinite && facts.targetMass > 0 ? facts.targetMass : 1
        return finite(skill / mass * state * weaponFactor(hit) * finite(facts.attackStagger))
    }

    /// The reaction of one hit, for a whole-number `roll` from 0 to 99.
    public static func reaction(
        _ hit: HitReactionHit, roll: Int, settings: StaggerSettings
    ) -> HitReaction {
        var reaction = HitReaction()
        if hit.isBash {
            reaction.largeRecoil = true
        } else {
            let magnitude = min(1, magnitude(hit) * finite(hit.perkMultiplier))
            let ranged = hit.handType == .bow || hit.handType == .crossbow
                || hit.handType == .staff
            let forced = (hit.isPlayerTarget && settings.playerAlwaysStaggered) || ranged
            let open = magnitude > 0 && !hit.facts.targetStaggered
            if open, forced || roll < settings.attackChance {
                reaction.staggerMagnitude = magnitude
            }
        }
        if hit.wasBlocked {
            reaction.blockHit = true
            reaction.attackerRecoils = hit.isMelee
        }
        return reaction
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }
}
