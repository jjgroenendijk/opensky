// Which ATKD attack an NPC's swing starts, chosen when the swing starts. The rules live
// in `NPCAttackPick`; see docs/engine/attack-data.md ("The AI's pick").

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyPhysics

extension CombatLoopRuntime.BehaviorDrive {
    /// Picks `actor`'s attack for a swing that starts now and notes when it started. An
    /// actor with no attack list, or with no attack that may start, swings plainly.
    @discardableResult
    func pickAttack(
        for swing: NPCSwing, bash: Bool = false, by actor: CombatActorObservation,
        at target: MeleeTarget, world: any CombatLoopWorld
    ) -> NPCAttack? {
        owner.pickedAttacks[actor.key] = nil
        guard !swing.shoots else { return nil }
        let list = world.combatAttacks(of: actor.key)
        guard !list.isEmpty else { return nil }
        let now = owner.stepSeconds
        var situation = NPCAttackSituation()
        situation.pool = bash ? .bash : swing.hand == .left ? .leftHand : .general
        let targetPhase = owner.behaviors[target.key]?.phase
        situation.targetIsStaggered = targetPhase == .staggered
        situation.targetBlocksTowardAttacker = targetPhase == .blocking
        situation.stamina = world.combatStamina(of: actor.key) ?? 1
        situation.secondsSinceUse = (owner.attackUses[actor.key] ?? [:])
            .mapValues { Float(now - $0) }
        situation.weights = world.combatStyle(of: actor.key)?.attackWeights ?? NPCAttackWeights()
        let direction = owner.facing(from: actor.feet, toward: target.feet, fallback: actor.yaw)
        guard
            let attack = NPCAttackPick.choose(
                list, situation: situation, aim: (actor.yaw, direction), roll: { owner.unitRoll() }
            )
        else { return nil }
        owner.pickedAttacks[actor.key] = attack
        owner.attackUses[actor.key, default: [:]][attack.event.lowercased()] = now
        return attack
    }
}

extension CombatLoopRuntime {
    /// A value in 0 ..< 1 from the combat loop's seeded stream.
    func unitRoll() -> Float {
        Float(staggerRandom.next() % 10000) / 10000
    }
}
