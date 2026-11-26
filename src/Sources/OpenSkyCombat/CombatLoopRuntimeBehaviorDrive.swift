// One engaged actor's step: its machine's inputs, its swing or cast, and where the blow
// lands. See docs/engine/combat-behavior.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import simd

/// What asking for a kill move at a swing gave.
private enum KillMoveStart {
    case started
    /// The swing's reach misses the target, so the attacker may still close in.
    case outOfReach
    /// The target is in reach, and the idle tree picked no kill move.
    case declined
}

extension CombatLoopRuntime.BehaviorDrive {
    func drive(
        actor: CombatActorObservation,
        influence: ActorMagicInfluence,
        target: MeleeTarget,
        world: any CombatLoopWorld
    ) {
        owner.targets[actor.key] = target.key
        if owner.behaviors[actor.key]?.phase != .staggered {
            owner.recoilers.remove(actor.key)
        }
        guard !owner.dodges(actor, goal: target.feet, world: world) else { return }
        let right = world.combatWeapon(of: actor.key)
        let shoots = right.handType == .bow
        let left = shoots ? nil : world.combatLeftWeapon(of: actor.key)
        let reachWeapon = owner.strikes[actor.key]?.weapon(right: right, left: left) ?? right
        track(target)
        let inputs = behaviorInputs(
            of: (actor, target), influence: influence,
            reach: (weapon: reachWeapon, shoots: shoots), world: world
        )
        let step = owner.stepBehavior(of: actor.key, inputs: inputs)
        let swing = swing(of: actor.key, started: step.startedAttack, right: right, left: left)
        if owner.behaviors[actor.key]?.pendingCast?.purpose == .shout {
            world.turnCombatActor(actor.key, toward: target.feet)
        }
        trackAttack(
            by: actor, at: target,
            attack: (step.startedAttack && !shoots, inputs.reach), world: world
        )
        if step.startedAttack, startSwing(swing, by: actor, at: target, world: world) {
            owner.parkBehavior(of: actor.key)
            return
        }
        if !step.startedAttack, closesInToKill(swing, by: actor, at: target, world: world) {
            owner.parkBehavior(of: actor.key)
            return
        }
        resolveCast(step, actor: actor.key, world: world)
        if step.reachedContact, !influence.isEthereal {
            if shoots {
                world.fireCombatArrow(CombatArrowShot(
                    shooter: actor, target: target,
                    targetVelocity: owner.targetTracks[target.key]?.velocity ?? .zero,
                    bow: right
                ))
            } else {
                for swung in swing.weapons {
                    resolveContact(actor: actor, weapon: swung, target: target, world: world)
                }
            }
        }
        if step.endedPursuit {
            world.resumeCombatPackage(for: actor.key)
        }
        if let command = step.command {
            route(command, pace: step.pace, actor: actor.key, world: world)
        }
    }

    /// From the start of a melee attack to its end the attacker faces the aim, which
    /// the track refreshes on its timer.
    func trackAttack(
        by actor: CombatActorObservation, at target: MeleeTarget,
        attack: (started: Bool, reach: Float), world: any CombatLoopWorld
    ) {
        let reach = attack.reach
        if attack.started {
            owner.attackTracks[actor.key] = CombatAttackTrack(
                target: target.key,
                aim: target.feet
            )
        }
        guard
            var track = owner.attackTracks[actor.key], track.target == target.key,
            owner.behaviors[actor.key]?.phase.isMeleeAttack == true
        else {
            owner.attackTracks[actor.key] = nil
            return
        }
        let aim = track.advance(
            by: CombatLoopRuntime.fixedStepSeconds, targetFeet: target.feet,
            distance: simd_distance(actor.feet, target.feet), reach: reach
        )
        owner.attackTracks[actor.key] = track
        world.turnCombatActor(actor.key, toward: aim)
    }

    /// Notes where `target` stands this step; a second actor in the same step reads the
    /// same two points.
    func track(_ target: MeleeTarget) {
        var track = owner.targetTracks[target.key] ?? TargetTrack(
            feet: target.feet,
            step: owner.stepSeconds
        )
        track.note(
            target.feet,
            step: owner.stepSeconds,
            seconds: CombatLoopRuntime.fixedStepSeconds
        )
        owner.targetTracks[target.key] = track
    }

    /// The casting half of one step: only when to begin, release or cancel. The caster
    /// runtime spends magicka and delivery decides the target. A refused begin drops the
    /// charge, so the actor swings again next step.
    func resolveCast(
        _ step: CombatBehaviorStep,
        actor: ReferenceKey,
        world: any CombatLoopWorld
    ) {
        if let option = step.startedCast, !world.beginCombatCast(option, by: actor) {
            owner.abandonCast(of: actor, world: world)
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
    func route(
        _ command: CombatMovementCommand,
        pace: CombatPace?,
        actor: ReferenceKey,
        world: any CombatLoopWorld
    ) {
        guard let destination = command.destination else {
            world.stopCombatMovement(of: actor)
            return
        }
        world.moveCombatActor(actor, to: destination, pace: pace)
    }

    /// The contact step: sweep the actor's reach at its target and apply
    /// whatever it found.
    func resolveContact(
        actor: CombatActorObservation,
        weapon: MeleeWeaponProfile,
        target: MeleeTarget,
        world: any CombatLoopWorld
    ) {
        strikeObjects(actor: actor, weapon: weapon, toward: target.feet, world: world)
        guard reaches(actor: actor, weapon: weapon, target: target) else { return }
        apply(from: actor, weapon: weapon, to: target.key, world: world)
    }

    /// A destructible object inside the swing takes the blow's damage, as from the player.
    func strikeObjects(
        actor: CombatActorObservation, weapon: MeleeWeaponProfile, toward point: SIMD3<Float>,
        world: any CombatLoopWorld
    ) {
        let settings = owner.settings
        let reach = MeleeSwing.reach(
            weapon: weapon,
            settings: settings,
            actorScale: actor.scale
        )
        let objects = world.combatDestructibles(
            within: reach + actor.capsule.height, of: actor.feet
        )
        guard !objects.isEmpty else { return }
        let volume = MeleeSwing.volume(
            feet: actor.feet, capsule: actor.capsule,
            facing: owner.facing(from: actor.feet, toward: point, fallback: actor.yaw),
            reach: reach
        )
        for hit in MeleeHitDetector.hits(swing: volume, targets: objects, attacker: actor.key) {
            let damage = landing(world).appliedDamage(
                by: actor.key,
                weapon: weapon,
                on: hit.target
            )
            world.damageCombatDestructible(hit.target, amount: damage)
        }
    }

    /// Which hand a swing that starts now uses, and with which weapons. A bow always
    /// shoots with the right hand.
    func swing(
        of key: ReferenceKey, started: Bool, right: MeleeWeaponProfile,
        left: MeleeWeaponProfile?
    ) -> NPCSwing {
        let shoots = right.handType == .bow
        if started, !shoots {
            owner.strikes[key, default: NPCStrikes()]
                .start(dual: left != nil && right.handType.isOneHandedMelee)
        }
        let hand = shoots ? .right : owner.strikes[key]?.hand ?? .right
        return NPCSwing(
            hand: hand,
            weapons: hand.weapons(right: right, left: left),
            shoots: shoots
        )
    }

    /// Plays the swing's clip and arms its swing spell, or starts a kill move instead.
    /// True when a kill move started.
    func startSwing(
        _ swing: NPCSwing, by actor: CombatActorObservation, at target: MeleeTarget,
        world: any CombatLoopWorld
    ) -> Bool {
        if !swing.shoots {
            switch startsKillMove(actor: actor, swing: swing, target: target, world: world) {
            case .started: return true
            case .outOfReach: owner.killMoveSeekers[actor.key] = target.key
            case .declined: break
            }
        }
        world.playCombatClip(swing.hand == .left ? .leftAttack : .attack, on: actor.key)
        if !swing.shoots, let weapon = swing.weapons.first {
            world.applyCombatSwingSpell(
                CombatNPCBlowLanding.blow(by: actor.key, weapon: weapon), at: target.key
            )
        }
        return false
    }

    /// A swing that starts a little out of reach closes in through its wind-up, so the
    /// kill move is asked again at each step until the target is in reach
    /// (docs/engine/paired-animations.md#kill-moves).
    func closesInToKill(
        _ swing: NPCSwing, by actor: CombatActorObservation, at target: MeleeTarget,
        world: any CombatLoopWorld
    ) -> Bool {
        guard owner.killMoveSeekers[actor.key] != nil else { return false }
        guard
            owner.killMoveSeekers[actor.key] == target.key,
            owner.behaviors[actor.key]?.phase == .windup
        else {
            owner.killMoveSeekers[actor.key] = nil
            return false
        }
        let attempt = startsKillMove(actor: actor, swing: swing, target: target, world: world)
        if attempt != .outOfReach {
            owner.killMoveSeekers[actor.key] = nil
        }
        return attempt == .started
    }

    /// A swing whose target is in reach may play a kill move instead.
    fileprivate func startsKillMove(
        actor: CombatActorObservation, swing: NPCSwing, target: MeleeTarget,
        world: any CombatLoopWorld
    ) -> KillMoveStart {
        guard let first = swing.weapons.first else { return .declined }
        guard reaches(actor: actor, weapon: first, target: target) else { return .outOfReach }
        let damage = swing.weapons.reduce(0) {
            $0 + landing(world).appliedDamage(by: actor.key, weapon: $1, on: target.key)
        }
        let started = world.startCombatKillMove(
            by: actor.key, on: target.key, damage: damage,
            action: KillMoveAttempt.action(hand: .right, power: true)
        )
        return started ? .started : .declined
    }

    func reaches(
        actor: CombatActorObservation, weapon: MeleeWeaponProfile, target: MeleeTarget
    ) -> Bool {
        let settings = owner.settings
        let volume = MeleeSwing.volume(
            feet: actor.feet,
            capsule: actor.capsule,
            facing: owner.facing(from: actor.feet, toward: target.feet, fallback: actor.yaw),
            reach: MeleeSwing.reach(weapon: weapon, settings: settings, actorScale: actor.scale)
        )
        return !MeleeHitDetector.hits(swing: volume, targets: [target], attacker: actor.key)
            .isEmpty
    }

    /// One landed blow. On the player it also plays the hit reaction, can recoil the
    /// attacker, and joins the trace.
    func apply(
        from actor: CombatActorObservation,
        weapon: MeleeWeaponProfile,
        to target: ReferenceKey,
        world: any CombatLoopWorld
    ) {
        guard
            let reaction = landing(world).land(
                from: actor.key, weapon: weapon, to: target, random: &owner.staggerRandom
            )
        else { return }
        if reaction.recoils {
            owner.noteStagger(of: actor.key)
            owner.recoilers.insert(actor.key)
        }
        owner.append(reaction.hit)
    }

    func landing(_ world: any CombatLoopWorld) -> CombatNPCBlowLanding {
        let settings = owner.settings
        return CombatNPCBlowLanding(
            world: world, settings: settings, skillUses: owner.skillUses,
            staggers: owner.staggers
        )
    }

    /// Radians from where `actor` faces to `point`, in -pi...pi.
    func facingError(
        of actor: CombatActorObservation,
        toward point: SIMD3<Float>
    ) -> Float {
        let turn = owner.facing(from: actor.feet, toward: point, fallback: actor.yaw) - actor
            .yaw
        return atan2f(sinf(turn), cosf(turn))
    }
}
