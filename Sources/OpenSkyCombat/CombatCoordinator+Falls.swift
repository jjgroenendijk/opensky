// Fall damage: a landing becomes health damage after the Mod Falling Damage perks and
// the difficulty rule. UESP "Skyrim:Damage", Fall Damage
// (docs/engine/combat.md#fall-damage).

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface

/// One landing and what it did, for `state` reads.
nonisolated public struct FallOutcome: Equatable, Sendable {
    public let actor: ReferenceKey
    public let height: Float
    public let speed: Float
    public let damage: Float

    public init(actor: ReferenceKey, height: Float, speed: Float, damage: Float) {
        self.actor = actor
        self.height = height
        self.speed = speed
        self.damage = damage
    }
}

extension CombatCoordinator {
    /// Hurts `actor` for a fall of `height` units that landed at `speed`. Water ends a
    /// fall before it lands, so a caller never reports one. Returns the damage dealt.
    @discardableResult
    public func applyFall(height: Float, speed: Float, to actor: ReferenceKey) -> Float {
        let damage = fallDamage(height: height, speed: speed, to: actor)
        if damage > 0 {
            _ = world.damageHealth(by: damage, of: actor)
            world.recordHealthHit(CombatHitRecord(damage: damage, kind: .other), on: actor)
        }
        lastFall = FallOutcome(actor: actor, height: height, speed: speed, damage: damage)
        return damage
    }

    func fallDamage(height: Float, speed: Float, to actor: ReferenceKey) -> Float {
        let isPlayer = actor == .player
        let base = falls.damage(height: height, speed: speed, isPlayer: isPlayer)
        let influence = world.magicInfluence(of: actor)
        guard base > 0, !influence.isEthereal, !influence.isParalysed else { return 0 }
        let perked = perkValue(
            base, at: .modFallingDamage, on: actor,
            subjects: PerkEvaluationSubjects(owner: actor)
        )
        // UESP: easier levels lower the player's fall damage; harder ones do not raise it.
        let scale = isPlayer ? min(difficultyMultipliers.damageToPlayer.value, 1) : 1
        return max(perked * scale, 0)
    }
}
