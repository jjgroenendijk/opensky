// A swing that would kill the actor in front can play a paired kill move instead.
// See docs/engine/paired-animations.md#kill-moves.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics

extension MeleeCombatRuntime {
    /// The kill-move idles sit beside the attack idles, so only an attack, not a bash,
    /// can start one. The damage is the hit this swing would deal the nearest actor.
    func startsKillMove(world: any MeleeCombatWorld) -> Bool {
        guard strikeKind == .normal || strikeKind == .power else { return false }
        let attacker = world.meleeAttacker
        let volume = MeleeSwing.volume(
            feet: attacker.feet,
            capsule: attacker.capsule,
            facing: attacker.facing,
            reach: strikeReach(actorScale: attacker.scale)
        )
        let hits = MeleeHitDetector.hits(
            swing: volume, targets: world.meleeTargets(), attacker: attacker.key
        )
        guard let target = hits.first?.target else { return false }
        let damage = resolveDamage(on: target, world: world)
        return world.startMeleeKillMove(
            on: target, damage: damage.applied, power: strikeKind == .power
        )
    }
}
