// Difficulty in the combat domain: the multipliers of the chosen level, and the
// Destruction experience rule. See docs/engine/combat.md, Difficulty.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyProgressionInterface

extension CombatCoordinator {
    public var difficultyMultipliers: DifficultyMultipliers {
        difficultySettings.multipliers(difficulty)
    }

    /// The player's Destruction spell use, with its experience divided above Adept.
    /// Any other use passes through unchanged.
    public func adjustingForDifficulty(_ use: SkillUseEvent) -> SkillUseEvent {
        guard
            use.actor == .player,
            case let .spellEffect(skill) = use.action,
            skill == Self.destructionIndex
        else { return use }
        return SkillUseEvent(
            actor: use.actor, action: use.action,
            amount: DifficultyDamage.destructionExperience(
                use.amount, level: difficulty, multipliers: difficultyMultipliers
            )
        )
    }

    /// The sidebar lines: each multiplier of the chosen level and its source.
    public var difficultyMultiplierLines: [String] {
        let resolved = difficultyMultipliers
        return [
            ("Damage dealt", resolved.damageByPlayer),
            ("Damage taken", resolved.damageToPlayer),
            ("Destruction experience divisor", resolved.experience)
        ].map { label, setting in
            String(format: "%@: %.2f (%@)", label, setting.value, setting.source)
        }
    }

    /// `Destruction` in `wbActorValueEnum`.
    static let destructionIndex: Int32 = 20
}
