// The opponents' half of one fixed step (issue #424, roadmap item 16.7): every
// engaged actor's machine advanced, its movement handed to 16.4, its clip asked
// for, and the blow it lands resolved through the player's own combat path.
//
// This file is what replaced `CombatLoopRuntimeTarget.swift`, which drove one
// designated dev target from a clock and said at length that it was a stand-in.
// A satellite for the same reason that one was: the parent is at its
// type-length limit, and the crowd loop reads better beside the single blow it
// resolves than inside the runtime's frame bookkeeping.
//
// Everything it calls to land a hit — `MeleeSwing.volume`,
// `MeleeHitDetector.hits`, `MeleeDamage.resolve`,
// `CombatLoopWorld.applyCombatDamage` — is the same path the player's own swing
// takes, unchanged from 15.7. What is new above it is who swings, when, from
// where, and whether they were still there to swing at all.
//
// ## Who gets a machine
//
// Living, not the player, and either hostile or shoved into the fight by a
// script or a blow. Sorted nearest-first and cut at
// `CombatLoopRuntime.maximumEngagedActors`, because every engaged actor asks the
// mover for a path and the mover's own crowd cap is the same number. What the
// cut refused is counted rather than dropped silently.
//
// Documented in docs/engine/combat.md.

import Foundation
import simd

extension CombatLoopRuntime {
    /// Advances every engaged actor by one fixed step and acts on what each did.
    func driveBehaviors(world: any CombatLoopWorld) {
        let actors = world.combatActors()
        let resident = Set(actors.map(\.key))
        // Over a snapshot of the keys, not the live view: retiring mutates the
        // dictionary being walked. Sorted so a run is reproducible even though
        // nothing here observes the order.
        for key in behaviors.keys.sorted() where !resident.contains(key) {
            retireBehavior(of: key)
        }
        for actor in actors where actor.isDead {
            parkBehavior(of: actor.key)
        }
        let player = world.combatPlayer
        let candidates = actors
            .filter { !$0.isDead && $0.key != player.key && shouldFight($0.key, world: world) }
            .sorted {
                (simd_distance($0.feet, player.feet), $0.key)
                    < (simd_distance($1.feet, player.feet), $1.key)
            }
        noteCrowdedOut(max(0, candidates.count - Self.maximumEngagedActors))
        for actor in candidates.prefix(Self.maximumEngagedActors) {
            drive(actor: actor, player: player, world: world)
        }
    }

    /// Whether `key` is somebody this step should think about at all.
    private func shouldFight(_ key: ReferenceKey, world: any CombatLoopWorld) -> Bool {
        world.combatHostility(of: key) == .hostile || engagesWithoutPerceiving(key)
    }

    /// One actor: build what it knows, step its machine, act on the answer.
    ///
    /// The target is the player. `StartCombat` records whatever target a script
    /// named, and refuses anything else, so `target(of:)` never resolves to a
    /// third party — NPC-versus-NPC combat is out of 16.7's scope and the native
    /// says so rather than half-simulating it.
    private func drive(
        actor: CombatActorObservation,
        player: MeleeAttacker,
        world: any CombatLoopWorld
    ) {
        let weapon = world.combatWeapon(of: actor.key)
        let step = stepBehavior(of: actor.key, inputs: CombatBehaviorInputs(
            actorPosition: actor.feet,
            targetPosition: player.feet,
            awareness: world.combatAwareness(of: actor.key, toward: player.key),
            reach: MeleeSwing.reach(
                weapon: weapon, settings: settings, actorScale: actor.scale
            ),
            healthFraction: world.combatHealthFraction(of: actor.key),
            isTargetAlive: true,
            isForced: engagesWithoutPerceiving(actor.key),
            casting: world.combatCasting(of: actor.key)
        ))
        if step.startedAttack {
            world.playCombatClip(.attack, on: actor.key)
        }
        resolveCast(step, actor: actor.key, world: world)
        if step.reachedContact {
            resolveContact(actor: actor, weapon: weapon, player: player, world: world)
        }
        if step.endedPursuit {
            world.resumeCombatPackage(for: actor.key)
        }
        if let command = step.command {
            route(command, actor: actor.key, world: world)
        }
    }

    /// The casting half of one step (issue #473, roadmap item 19.10).
    ///
    /// Begin, release and cancel all land here rather than beside the melee
    /// contact, because a cast is not resolved by this layer at all: the caster
    /// runtime spends the magicka and the 19.8 delivery decides what the spell
    /// reaches. What this layer owns is only *when*.
    ///
    /// A refused begin drops the machine's charge in the same step, so an actor
    /// whose magicka fell between the decision and the call is back to swinging
    /// on the next one instead of holding a cast the runtime never started.
    private func resolveCast(
        _ step: CombatBehaviorStep,
        actor: ReferenceKey,
        world: any CombatLoopWorld
    ) {
        if let option = step.startedCast, !world.beginCombatCast(option, by: actor) {
            abandonCast(of: actor, world: world)
        }
        if let option = step.releasedCast {
            world.releaseCombatCast(option, by: actor)
        }
        if step.cancelledCast {
            world.cancelCombatCast(by: actor)
        }
    }

    /// Hands one movement decision to the 16.4 mover, which owns the path and
    /// the capsule. A point no navmesh reaches is refused, and the machine's own
    /// re-path interval is what asks again.
    private func route(
        _ command: CombatMovementCommand,
        actor: ReferenceKey,
        world: any CombatLoopWorld
    ) {
        guard let destination = command.destination else {
            world.stopCombatMovement(of: actor)
            return
        }
        world.moveCombatActor(actor, to: destination)
    }

    /// The contact step: sweep the actor's reach at the player and apply
    /// whatever it found.
    private func resolveContact(
        actor: CombatActorObservation,
        weapon: MeleeWeaponProfile,
        player: MeleeAttacker,
        world: any CombatLoopWorld
    ) {
        let volume = MeleeSwing.volume(
            feet: actor.feet,
            capsule: actor.capsule,
            facing: facing(from: actor.feet, toward: player.feet, fallback: actor.facing),
            reach: MeleeSwing.reach(
                weapon: weapon, settings: settings, actorScale: actor.scale
            )
        )
        let hits = MeleeHitDetector.hits(
            swing: volume,
            targets: [MeleeTarget(key: player.key, feet: player.feet, capsule: player.capsule)],
            attacker: actor.key
        )
        guard !hits.isEmpty else { return }
        apply(from: actor, weapon: weapon, to: player.key, world: world)
    }

    /// One landed blow: the pinned 15.4 damage formula, the health write, and
    /// the player's hit reaction.
    private func apply(
        from actor: CombatActorObservation,
        weapon: MeleeWeaponProfile,
        to player: ReferenceKey,
        world: any CombatLoopWorld
    ) {
        let damage = MeleeDamage.resolve(
            weapon: weapon,
            block: world.combatBlock(of: player),
            settings: settings,
            bonusMultiplier: world.combatBlockMultiplier(of: player)
        )
        world.applyCombatDamage(damage.applied, to: player)
        // The other direction of the same dispatch the player's own swing
        // makes (issue #375): a script attached to the player takes `OnHit`
        // with the attacking actor as `akAggressor`.
        world.reportScriptHit(ScriptHitEvent(
            target: player,
            aggressor: actor.key,
            source: weapon.weapon,
            isBlocked: damage.wasBlocked
        ))
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
    ///
    /// A fighting actor turns to face what it is swinging at because it decided
    /// to close on it; the dev target turned here because it had no decisions,
    /// and the note that said so is gone with it.
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
