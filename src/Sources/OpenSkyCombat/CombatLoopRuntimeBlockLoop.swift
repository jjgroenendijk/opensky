// The runtime's side of the block loop: what the target does, whether the actor can
// block or bash, and a bash's pick, line, and reach. See docs/engine/combat-blocking.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

extension CombatLoopRuntime.BehaviorDrive {
    /// Fills what the block loop reads. A bow blocks and bashes with nothing here, because
    /// an archer runs no block loop; bare hands bash nothing and block only with a shield.
    func fillBlockInputs(
        _ inputs: inout CombatBehaviorInputs,
        of fight: (actor: CombatActorObservation, target: MeleeTarget),
        reach: (weapon: MeleeWeaponProfile, shoots: Bool), world: any CombatLoopWorld
    ) {
        let (actor, target) = fight
        inputs.target = targetActions(of: target, isPlayer: inputs.targetIsPlayer, world: world)
        let hasShield = world.combatShieldRating(of: actor.key) != nil
        inputs.canBlock = !reach.shoots && (reach.weapon.handType != .handToHand || hasShield)
        inputs.canBash = inputs.canBlock
            && inputs.distance <= bashReach(of: actor) + inputs.target.radius
            && world.combatAttacks(of: actor.key).contains {
                $0.properties?.flags.contains(.bash) == true
            }
    }

    /// A bash reaches `fCombatBashReach` whatever the weapon.
    func bashReach(of actor: CombatActorObservation) -> Float {
        max(0, owner.powerAttacks.bashReach) * actor.scale
    }

    /// Picks the bash the machine started. No pick sends the machine back; a pick says the
    /// Bash line. True when the bash goes on.
    @discardableResult
    func startBash(
        by actor: CombatActorObservation, at target: MeleeTarget, world: any CombatLoopWorld
    ) -> Bool {
        let swing = NPCSwing(
            hand: .right,
            weapons: [world.combatWeapon(of: actor.key)],
            shoots: false
        )
        guard pickAttack(for: swing, bash: true, by: actor, at: target, world: world) != nil else {
            owner.cancelBash(of: actor.key)
            return false
        }
        world.sayCombatBash(by: actor.key, to: target.key)
        let clip: CombatActorClip = world.combatShieldRating(of: actor.key) == nil ? .bash
            : .shieldBash
        if !world.playCombatClip(clip, on: actor.key) {
            world.playCombatClip(.attack, on: actor.key)
        }
        return true
    }

    private func targetActions(
        of target: MeleeTarget, isPlayer: Bool, world: any CombatLoopWorld
    ) -> CombatTargetActions {
        var actions = CombatTargetActions()
        actions.radius = target.capsule.radius
        actions.isBlocking = world.combatBlock(of: target.key) != nil
        actions.isRecoiling = owner.isRecoiling(target.key)
        if isPlayer {
            guard let melee = world.combatPlayerMelee() else { return actions }
            actions.attack = switch melee.phase {
            case .windup: .draw
            case .swinging, .contact: .swing
            case .idle, .recovery: .none
            }
            actions.isPowerAttack = melee.kind.isPowerAttack
            actions.fightsInMelee = melee.weapon.handType != .bow
            actions.reach = reach(of: melee.weapon, scale: world.combatPlayer.scale, unarmed: nil)
            return actions
        }
        let phase = owner.behaviors[target.key]?.phase
        actions.attack = phase == .windup ? .draw : phase == .contact ? .swing : .none
        let picked = owner.pickedAttacks[target.key]
        actions.isPowerAttack = picked?.isPowerAttack ?? false
        actions.strikeAngleDegrees = picked?.data.strikeAngle ?? CombatTargetActions.hitConeDegrees
        let weapon = world.combatWeapon(of: target.key)
        actions.fightsInMelee = weapon.handType != .bow
        if let observed = world.combatActor(key: target.key) {
            actions.reach = reach(of: weapon, scale: observed.scale, unarmed: observed.unarmedReach)
        }
        return actions
    }

    private func reach(of weapon: MeleeWeaponProfile, scale: Float, unarmed: Float?) -> Float {
        MeleeSwing.reach(
            weapon: weapon, settings: owner.settings, actorScale: scale, unarmedReach: unarmed
        )
    }
}
