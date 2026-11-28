// When an actor in reach starts its next attack: a roll of its attack chance, repeated
// after a short wait. See docs/formats/combat-style.md ("Attack and bash chances").

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions

nonisolated extension CombatBehaviorMachine {
    /// The most the time since the last hit frame raises the attack chance, reached after
    /// `lastAttackBonusSeconds`.
    static let lastAttackBonus: Float = 1.5
    static let lastAttackBonusSeconds: Float = 5

    /// The attack chance for this roll, with the staggered-target, blocking, and last-attack
    /// terms.
    func attackChance(_ inputs: CombatBehaviorInputs) -> Float {
        var chance = settings.attackChance ?? 1
        if inputs.targetIsStaggered {
            chance *= settings.staggeredAttackMult
        } else if phase == .blocking, let loop = settings.blockLoop {
            chance *= inputs.target.attack == .none ? loop.attackChanceBlockingMult
                : loop.attackChanceBlockingSwingMult
        }
        if secondsSinceShot.isFinite {
            let share = min(max(0, secondsSinceShot), Self.lastAttackBonusSeconds)
                / Self.lastAttackBonusSeconds
            chance *= 1 + (Self.lastAttackBonus - 1) * share
        }
        return chance
    }

    /// Rolls the attack chance when a roll is due; a failed roll waits `attackRollSeconds`.
    /// Without an attack chance, the attack interval is the wait. With a weapon in each
    /// hand, the right hand rolls, then the left, and the first to pass attacks.
    mutating func rollsAttack(_ inputs: CombatBehaviorInputs) -> Bool {
        attackHand = nil
        guard settings.attackChance != nil else {
            return phaseSeconds >= settings.attackIntervalSeconds
        }
        guard phaseSeconds >= nextAttackRoll else { return false }
        nextAttackRoll = phaseSeconds + settings.attackRollSeconds
        let chance = attackChance(inputs)
        if Float(random.percent()) / 100 < chance {
            attackHand = inputs.holdsTwoWeapons ? .right : nil
            return true
        }
        guard inputs.holdsTwoWeapons, Float(random.percent()) / 100 < chance else { return false }
        attackHand = .left
        return true
    }
}
