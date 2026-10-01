// How much health a landed swing takes off, and what a block leaves of it.
// Every result is a fraction in `0...1`; the readout multiplies by 100.
// The blocker's and the attacker's bonus terms stay separate, because they act
// on opposite sides of the hit. Documented in docs/engine/melee-damage.md.

import Foundation
import OpenSkyCombatInterface
import OpenSkyPhysics

/// What the blocker was holding, which picks the formula branch.
nonisolated public enum MeleeBlockKind: Equatable, Sendable {
    /// Blocking with a weapon or a torch: scales on the *attacker's* base
    /// weapon damage.
    case weapon
    /// Blocking with a shield: scales on the shield's own base armour rating.
    case shield(baseArmorRating: Float)
}

/// One resolved hit's damage accounting, kept whole so a readout can explain a
/// number rather than just show it.
nonisolated public struct MeleeDamageResult: Equatable, Sendable {
    /// WEAP base damage before anything reduced it.
    public let base: Float
    /// The fraction the block absorbed, after the cap. Zero when unblocked.
    public let blockedFraction: Float
    /// What actually comes off health.
    public let applied: Float
    /// The attacker's fortify multiplier this result was resolved with, so a
    /// readout can show why the number is not the WEAP one. 1 for a character
    /// with no fortify effect.
    public let attackMultiplier: Float

    public init(
        base: Float,
        blockedFraction: Float,
        applied: Float,
        attackMultiplier: Float = 1
    ) {
        self.base = base
        self.blockedFraction = blockedFraction
        self.applied = applied
        self.attackMultiplier = attackMultiplier
    }

    public var wasBlocked: Bool {
        blockedFraction > 0
    }

    /// Whether a fortify effect moved the number away from the WEAP base.
    public var wasFortified: Bool {
        attackMultiplier != 1
    }
}

nonisolated public enum MeleeDamage: Sendable {
    /// The Block skill assumed for a character with no skill table: 15, the starting value
    /// for a race with no Block bonus (UESP "Skyrim:Block").
    public static let defaultBlockSkill: Float = 15

    /// What one landed swing takes off the target's health. `block` is nil when the
    /// target was not blocking. `bonusMultiplier` is the blocker's
    /// `CombatFortifyBonus.block`; `attackMultiplier` the attacker's `melee(handType:)`.
    public static func resolve(
        weapon: MeleeWeaponProfile,
        block: MeleeBlockKind?,
        settings: CombatSettings,
        blockSkill: Float = defaultBlockSkill,
        isPowerAttack: Bool = false,
        bonusMultiplier: Float = 1,
        attackMultiplier: Float = 1
    ) -> MeleeDamageResult {
        let base = weapon.damage.isFinite ? max(0, weapon.damage) : 0
        let attack = attackMultiplier.isFinite ? max(0, attackMultiplier) : 1
        guard let block else {
            return MeleeDamageResult(
                base: base,
                blockedFraction: 0,
                applied: base * attack,
                attackMultiplier: attack
            )
        }
        let fraction = blockedFraction(
            attackerDamage: base,
            block: block,
            settings: settings,
            blockSkill: blockSkill,
            isPowerAttack: isPowerAttack,
            bonusMultiplier: bonusMultiplier
        )
        return MeleeDamageResult(
            base: base,
            blockedFraction: fraction,
            applied: base * attack * (1 - fraction),
            attackMultiplier: attack
        )
    }

    /// The blocked fraction on its own, capped at `fBlockMax`.
    public static func blockedFraction(
        attackerDamage: Float,
        block: MeleeBlockKind,
        settings: CombatSettings,
        blockSkill: Float = defaultBlockSkill,
        isPowerAttack: Bool = false,
        bonusMultiplier: Float = 1
    ) -> Float {
        let skill = blockSkill.isFinite ? max(0, blockSkill) : 0
        let skillTerm = 1 + skill * settings.blockSkillMult.value / 100
        let branch: Float = switch block {
        case .weapon:
            settings.blockWeaponBase.value
                + settings.blockWeaponScaling.value * max(0, attackerDamage) * skillTerm / 100
        case let .shield(rating):
            settings.shieldBaseFactor.value
                + settings.shieldScalingFactor.value
                * (rating.isFinite ? max(0, rating) : 0) * skillTerm / 100
        }
        let bonus = bonusMultiplier.isFinite ? max(0, bonusMultiplier) : 1
        let power = isPowerAttack ? settings.blockPowerAttackMult.value : 1
        let raw = branch * bonus * power
        let cap = settings.blockMax.value.isFinite ? max(0, settings.blockMax.value) : 0
        guard raw.isFinite else { return 0 }
        return min(max(raw, 0), cap)
    }
}
