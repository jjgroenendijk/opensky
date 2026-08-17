// How much health a landed swing takes off, and what a block leaves of it
// (issue #195, roadmap item 15.4, scope point 6).
//
// The formula's *shape* is UESP's, quoted rather than paraphrased.
// "Skyrim:Block" gives two, one per block type, and both are the same:
//
//   weapon: blocked = fBlockWeaponBase
//                     + fBlockWeaponScaling * attackerWeaponBaseDamage
//                       * (1 + blockSkill * fBlockSkillMult / 100) / 100
//   shield: blocked = fShieldBaseFactor
//                     + fShieldScalingFactor * shieldBaseArmorRating
//                       * (1 + blockSkill * fBlockSkillMult / 100) / 100
//
// then multiplied by the Shield Wall perk term, the Fortify Block enchantment
// and potion terms, and by `fBlockPowerAttackMult` when the incoming attack is
// a power attack, and finally capped at `fBlockMax`.
//
// The formula's *numbers* are the install's, and they are not the ones UESP
// prints — see `CombatSettings` for the full reading and the values. The one
// consequence visible here is the trailing `/ 100` on each scaling term: the
// install states the base terms and the cap as fractions (0.300, 0.450, 0.700)
// while the scaling terms stay percentage points per unit, so mixing them
// needs exactly one conversion and this is where it goes. Every quantity this
// file returns is a fraction in `0...1`; nothing here is a percentage, and the
// readout multiplies by 100 at the very end.
//
// Two terms were deliberately absent when this was written. Perks and Fortify
// Block effects were M18's — there was no perk tree and no magic effect in this
// engine to read them from — so they enter as a single `bonusMultiplier`
// defaulting to 1, which is exactly what the formula reduces to for a character
// with neither. The Block *skill* is in the same position: `ActorValues` carries
// health, magicka and stamina only, and the rest of the actor-value table is
// M18. So `blockSkill` is a parameter with a documented default of 15, the value
// UESP gives for a starting skill, rather than a number invented here or
// silently taken as zero.
//
// Issue #472 (roadmap item 19.9) fills in the enchantment and potion halves of
// both open terms, and adds the one the attacker's side of the formula was
// missing:
//
// * `bonusMultiplier` is the *block* bonus, which is where the quoted formula
//   puts it, and `CombatFortifyBonus.block` now supplies it from Block Modifier
//   and Block Power Modifier.
// * `attackMultiplier` is new. UESP "Skyrim:Weapons" gives the attacker's side as
//   `... * (1 + perk effects) * (1 + item effects) * (1 + potion effect)`, and
//   `ArcheryDamage` has carried that term since item 15.5 while this file had
//   nowhere to put it — a Fortify One-Handed effect had no way to change a melee
//   number. `CombatFortifyBonus.melee(handType:)` supplies it.
//
// The two are separate parameters rather than one because they act on opposite
// sides of the exchange: an attacker's fortify raises the damage dealt, and a
// blocker's fortify raises the fraction absorbed. Folding them together would
// let the target's ring change the attacker's damage.
//
// The attack term multiplies *after* the blocked fraction is computed, not
// before: the quoted block formula scales on "attackerWeaponBaseDamage", which is
// the WEAP number rather than the enchanted one, so a fortified attacker deals
// more through a block without the block growing to meet it.
//
// One surprising thing about the weapon branch is worth stating because it
// looks like a bug: the scaling term uses the *attacker's* weapon damage, not
// the blocker's. UESP is explicit about this and works through the creature
// case (an unarmed attacker gives a flat base) to show it is intended. Reading
// it the other way would make a warhammer the best thing to block with.
//
// Nothing here throws and nothing here reaches the world. It is a pure
// function of numbers, which is what makes the acceptance test's "damage
// matches WEAP data, blocking reduces it per the pinned formula" a plain
// arithmetic assertion.
//
// Documented in docs/engine/melee-combat.md.

import Foundation

/// What the blocker was holding, which picks the formula branch.
nonisolated enum MeleeBlockKind: Equatable, Sendable {
    /// Blocking with a weapon or a torch: scales on the *attacker's* base
    /// weapon damage.
    case weapon
    /// Blocking with a shield: scales on the shield's own base armour rating.
    case shield(baseArmorRating: Float)
}

/// One resolved hit's damage accounting, kept whole so a readout can explain a
/// number rather than just show it.
nonisolated struct MeleeDamageResult: Equatable, Sendable {
    /// WEAP base damage before anything reduced it.
    let base: Float
    /// The fraction the block absorbed, after the cap. Zero when unblocked.
    let blockedFraction: Float
    /// What actually comes off health.
    let applied: Float
    /// The attacker's fortify multiplier this result was resolved with, so a
    /// readout can show why the number is not the WEAP one. 1 for a character
    /// with no fortify effect.
    let attackMultiplier: Float

    init(
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

    var wasBlocked: Bool {
        blockedFraction > 0
    }

    /// Whether a fortify effect moved the number away from the WEAP base.
    var wasFortified: Bool {
        attackMultiplier != 1
    }
}

nonisolated enum MeleeDamage {
    /// The Block skill a character with no skill table is assumed to have.
    /// UESP "Skyrim:Block" gives 15 as the starting value for every race with
    /// no Block bonus; the real per-actor number arrives with the rest of the
    /// actor-value table in M18.
    static let defaultBlockSkill: Float = 15

    /// What one landed swing takes off the target's health.
    ///
    /// - Parameters:
    ///   - weapon: the attacker's swing profile; `damage` is the base.
    ///   - block: what the target was blocking with, or nil when it was not
    ///     blocking.
    ///   - settings: the resolved GMSTs.
    ///   - blockSkill: the target's Block skill.
    ///   - isPowerAttack: whether the incoming attack was a power attack.
    ///   - bonusMultiplier: the *blocker's* perk, enchantment and potion terms,
    ///     folded into one, which is where the quoted formula puts them. 1 for a
    ///     character with none. `CombatFortifyBonus.block` supplies it.
    ///   - attackMultiplier: the *attacker's* perk, enchantment and potion terms
    ///     (issue #472). 1 for a character with none.
    ///     `CombatFortifyBonus.melee(handType:)` supplies it.
    static func resolve(
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
    static func blockedFraction(
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
