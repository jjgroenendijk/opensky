// The opponent's half of one fixed step (issue #374, roadmap item 15.7, scope
// points 2 and 3): the dev target's clock advanced, its clip asked for, and the
// blow it lands resolved through the player's own combat path.
//
// A satellite of `CombatLoopRuntime` because the parent is at its type-length
// limit, and because this is the one part of the loop that is explicitly
// temporary: when M16 replaces the clock with a mind, this file is what it
// replaces. Everything it calls — `MeleeSwing.volume`, `MeleeHitDetector.hits`,
// `MeleeDamage.resolve`, `CombatLoopWorld.applyCombatDamage` — is the same path
// the player's own swing takes, so the AI that arrives inherits a working blow
// rather than a second implementation of one.
//
// Two things this does that a real opponent would do differently, stated rather
// than hidden:
//
// * **It turns to face the player at the contact step.** The placement facing an
//   ACHR carries is where the level designer pointed it, which is almost never
//   at whoever walked in; without the turn the stand-in would swing at a wall
//   forever and the loop would never close. A real opponent turns because it
//   decided to, and this one turns because it has no decisions.
// * **It never moves.** A player who steps out of reach is safe, permanently.
//   Locomotion for an NPC needs the behavior graph M16 brings, and faking a
//   slide toward the player would put movement in the engine that nothing else
//   agrees with.
//
// Documented in docs/engine/combat.md.

import Foundation
import simd

extension CombatLoopRuntime {
    /// Advances the opponent by one fixed step and acts on what it did.
    func driveDevTarget(world: any CombatLoopWorld) {
        guard let key = devTarget else { return }
        guard
            let actor = world.combatActors().first(where: { $0.key == key }),
            !actor.isDead
        else {
            // The target died or its cell unloaded. Park the clock rather than
            // clearing the designation: a corpse is still the thing the player
            // was fighting, and the readout should keep saying so.
            parkDevTargetDriver()
            return
        }
        let step = stepDevTargetDriver()
        if step.startedAttack {
            world.playCombatClip(.attack, on: key)
        }
        guard step.reachedContact else { return }
        resolveDevTargetContact(actor: actor, world: world)
    }

    /// The contact step: sweep the opponent's reach at the player and apply
    /// whatever it found.
    private func resolveDevTargetContact(
        actor: CombatActorObservation,
        world: any CombatLoopWorld
    ) {
        let player = world.combatPlayer
        let volume = MeleeSwing.volume(
            feet: actor.feet,
            capsule: actor.capsule,
            facing: facing(from: actor.feet, toward: player.feet, fallback: actor.facing),
            reach: MeleeSwing.reach(
                weapon: devTargetWeapon, settings: settings, actorScale: actor.scale
            )
        )
        let hits = MeleeHitDetector.hits(
            swing: volume,
            targets: [MeleeTarget(key: player.key, feet: player.feet, capsule: player.capsule)],
            attacker: actor.key
        )
        guard !hits.isEmpty else { return }
        apply(from: actor, to: player.key, world: world)
    }

    /// One landed blow: the pinned 15.4 damage formula, the health write, and
    /// the player's hit reaction.
    private func apply(
        from actor: CombatActorObservation,
        to player: ReferenceKey,
        world: any CombatLoopWorld
    ) {
        let damage = MeleeDamage.resolve(
            weapon: devTargetWeapon,
            block: world.combatBlock(of: player),
            settings: settings
        )
        world.applyCombatDamage(damage.applied, to: player)
        // The magnitude is written before the event so the recoil behavior
        // reads this blow's number rather than the previous one's, which is the
        // same write-then-raise order the melee runtime uses for a stagger.
        let played = damage.applied > 0 && raiseRecoil(magnitude: damage.applied, world: world)
        append(CombatIncomingHit(
            aggressor: actor.key,
            damage: damage,
            playedReaction: played,
            attackID: nextAttackID()
        ))
    }

    /// Raises the census-named hit reaction on the player's graph, magnitude
    /// first.
    ///
    /// - Returns: whether the graph declared the event, which is the graph's own
    ///   answer rather than an assumption about it.
    private func raiseRecoil(magnitude: Float, world: any CombatLoopWorld) -> Bool {
        world.writeCombatVariable(.real(magnitude), named: CombatGraphNames.recoilMagnitude)
        return world.raiseCombatEvent(CombatGraphNames.recoilStart, on: nil)
    }

    /// Yaw from `origin` toward `target` in the locomotion bridge's convention,
    /// falling back to the placement facing when the two are on the same spot.
    private func facing(
        from origin: SIMD3<Float>,
        toward target: SIMD3<Float>,
        fallback: Float
    ) -> Float {
        let offset = target - origin
        guard simd_length_squared(SIMD2(offset.x, offset.y)) > 1e-6 else { return fallback }
        return atan2f(offset.y, offset.x)
    }
}
