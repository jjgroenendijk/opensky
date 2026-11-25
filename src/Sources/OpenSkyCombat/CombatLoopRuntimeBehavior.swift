// The opponents' half of one fixed step: each engaged actor's machine, movement, clip,
// and blow, landed through the player's own hit path. Engaged means living, not the
// player or its ally, and hostile or pushed in. Nearest first, cut at
// `maximumEngagedActors` (the mover's crowd cap); the cut is counted. Allies take what
// is left of the cap. See docs/engine/combat-behavior.md.

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

extension CombatLoopRuntime {
    /// Advances every engaged actor by one fixed step and acts on what each did.
    /// - Returns: the hostility read for each living actor, so the step asks once.
    @discardableResult
    func driveBehaviors(world: any CombatLoopWorld) -> [ReferenceKey: ActorHostility] {
        BehaviorDrive(owner: self).driveBehaviors(world: world)
    }

    /// One actor: build what it knows, step its machine, act on the answer. The
    /// target is the player or its ally for a foe, and a foe for an ally.
    func drive(
        actor: CombatActorObservation,
        influence: ActorMagicInfluence,
        target: MeleeTarget,
        world: any CombatLoopWorld
    ) {
        BehaviorDrive(owner: self).drive(
            actor: actor,
            influence: influence,
            target: target,
            world: world
        )
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

/// Whom one actor may fight this step.
/// How the living actors stand toward the fight this step.
private struct CombatStances {
    var hostility: [ReferenceKey: ActorHostility] = [:]
    var influences: [ReferenceKey: ActorMagicInfluence] = [:]
    var ignoring: Set<ReferenceKey> = []
}

private struct TargetChoices {
    /// The player's allies.
    let allies: [MeleeTarget]
    /// The nearest NPC the actor fights, if any.
    let foe: MeleeTarget?
    /// The actor fights the player's side: it is hostile, frenzied, or pushed in.
    var fightsPlayer = false
}

/// What asking for a kill move at a swing gave.
private enum KillMoveStart {
    case started
    /// The swing's reach misses the target, so the attacker may still close in.
    case outOfReach
    /// The target is in reach, and the idle tree picked no kill move.
    case declined
}

extension CombatLoopRuntime {
    /// Drives each fighter's behaviour: targets, inputs, movement, and swings.
    struct BehaviorDrive {
        let owner: CombatLoopRuntime

        @discardableResult
        func driveBehaviors(world: any CombatLoopWorld) -> [ReferenceKey: ActorHostility] {
            let actors = world.combatActors()
            settleRoster(actors)
            let player = world.combatPlayer
            let standing = stances(of: actors, player: player.key, world: world)
            var hostility = standing.hostility
            let (influences, ignoring) = (standing.influences, standing.ignoring)
            for actor in actors where influences[actor.key]?.refusesCombat == true
                || ignoring.contains(actor.key)
            {
                holdStill(actor.key, world: world)
            }
            owner.watchAggroRadii(actors, hostility: &hostility, ignoring: ignoring, world: world)
            owner.recruitAssistants(
                among: actors, hostility: &hostility, ignoring: ignoring, world: world
            )
            owner.scanFoes(actors, world: world)
            let foes = owner.actorFoes(among: actors, world: world)
            let candidates = actors
                .filter { actor in
                    guard
                        let stance = hostility[actor.key],
                        owner.commanders[actor.key] != player.key
                    else { return false }
                    return fights(
                        actor.key, stance: stance, influence: influences[actor.key] ?? .none,
                        hasFoe: foes[actor.key] != nil
                    ) && !ignoring.contains(actor.key)
                }
                .sorted {
                    (simd_distance($0.feet, player.feet), $0.key)
                        < (simd_distance($1.feet, player.feet), $1.key)
                }
            owner.noteCrowdedOut(max(0, candidates.count - CombatLoopRuntime.maximumEngagedActors))
            let allies = playerAllies(among: actors, player: player.key)
            let driven = candidates.prefix(CombatLoopRuntime.maximumEngagedActors)
            for actor in driven {
                let influence = influences[actor.key] ?? .none
                var choices = TargetChoices(allies: allies, foe: foes[actor.key])
                choices.fightsPlayer = hostility[actor.key] == .hostile || influence.isFrenzied
                    ||
                    (owner.engagesWithoutPerceiving(actor.key) && !owner.retaliating
                        .contains(actor.key))
                owner.drive(
                    actor: actor, influence: influence,
                    target: target(of: actor, player: player, choices: choices, world: world),
                    world: world
                )
            }
            owner.driveAllies(
                among: actors,
                engaging: (
                    BehaviorDrive
                        .meleeTargets(driven.filter { owner.behaviors[$0.key]?.isEngaged == true }),
                    CombatLoopRuntime.maximumEngagedActors - driven.count
                ),
                influences: influences, world: world
            )
            return hostility
        }

        /// How each living actor other than the player stands toward the fight.
        private func stances(
            of actors: [CombatActorObservation], player: ReferenceKey, world: any CombatLoopWorld
        ) -> CombatStances {
            var stances = CombatStances()
            for actor in actors where !actor.isDead && actor.key != player {
                stances.hostility[actor.key] = world.combatHostility(of: actor.key)
                stances.influences[actor.key] = world.combatInfluence(of: actor.key)
                if world.combatIgnoredByPackage(actor.key) {
                    stances.ignoring.insert(actor.key)
                }
            }
            return stances
        }

        /// The living allies of the player, as targets.
        func playerAllies(
            among actors: [CombatActorObservation], player: ReferenceKey
        ) -> [MeleeTarget] {
            BehaviorDrive
                .meleeTargets(actors.filter { !$0.isDead && owner.commanders[$0.key] == player })
        }

        /// Whether an actor that is free to fight does: it is hostile to the player, frenzied,
        /// pushed in, or has an NPC foe.
        func fights(
            _ key: ReferenceKey, stance: ActorHostility, influence: ActorMagicInfluence,
            hasFoe: Bool
        ) -> Bool {
            guard !influence.refusesCombat else { return false }
            return stance == .hostile || influence.isFrenzied || owner.engagesWithoutPerceiving(key)
                || hasFoe
        }

        /// Retires the machines of actors that left and parks those of the dead.
        func settleRoster(_ actors: [CombatActorObservation]) {
            let resident = Set(actors.map(\.key))
            // Over a snapshot of the keys, not the live view: retiring mutates the
            // dictionary being walked. Sorted so a run is reproducible even though
            // nothing here observes the order.
            for key in owner.behaviors.keys.sorted() where !resident.contains(key) {
                owner.retireBehavior(of: key)
            }
            for actor in actors where actor.isDead {
                owner.parkBehavior(of: actor.key)
            }
        }

        static func meleeTargets(
            _ actors: some Sequence<CombatActorObservation>
        ) -> [MeleeTarget] {
            actors.map { MeleeTarget(key: $0.key, feet: $0.feet, capsule: $0.capsule) }
        }

        /// A foe of the player fights the nearest of the player, the player's allies it has
        /// seen, and its NPC foe. An actor that is no foe of the player fights its NPC foe. A
        /// script's `StartCombat` keeps it on the player.
        fileprivate func target(
            of actor: CombatActorObservation,
            player: MeleeAttacker,
            choices: TargetChoices,
            world: any CombatLoopWorld
        ) -> MeleeTarget {
            let you = MeleeTarget(key: player.key, feet: player.feet, capsule: player.capsule)
            if !choices.fightsPlayer, let foe = choices.foe {
                return foe
            }
            guard !owner.isForcedOntoPlayer(actor.key) else { return you }
            let seen = choices.allies.filter {
                world.combatAwareness(of: actor.key, toward: $0.key).isDetected
            }
            // An undetected player does not pull the actor away from a foe it fights.
            let knowsPlayer = choices.foe == nil || owner.engagesWithoutPerceiving(actor.key)
                || world.combatAwareness(of: actor.key, toward: player.key).isDetected
            let options = (knowsPlayer ? [you] : []) + seen + (choices.foe.map { [$0] } ?? [])
            return CombatAllyRule.nearest(options, to: actor.feet) ?? you
        }

        /// Calm "lowers the Aggression" and Paralysis stops all movement: an actor in a
        /// fight leaves it and stands where it is.
        func holdStill(_ key: ReferenceKey, world: any CombatLoopWorld) {
            guard let machine = owner.behaviors[key], machine.phase != .idle else { return }
            owner.parkBehavior(of: key)
            world.stopCombatMovement(of: key)
        }

        /// What the actor's machine is told this step.
        func behaviorInputs(
            of fight: (actor: CombatActorObservation, target: MeleeTarget),
            influence: ActorMagicInfluence,
            reach: (weapon: MeleeWeaponProfile, shoots: Bool), world: any CombatLoopWorld
        ) -> CombatBehaviorInputs {
            let settings = owner.settings
            let (actor, target) = fight
            var inputs = CombatBehaviorInputs(
                actorPosition: actor.feet,
                targetPosition: target.feet,
                awareness: world.combatAwareness(of: actor.key, toward: target.key),
                reach: MeleeSwing.reach(
                    weapon: reach.weapon, settings: settings, actorScale: actor.scale
                ),
                healthFraction: world.combatHealthFraction(of: actor.key),
                isTargetAlive: true,
                isForced: owner.engagesWithoutPerceiving(actor.key),
                casting: world.combatCasting(of: actor.key),
                influence: influence,
                temperament: world.combatTemperament(of: actor.key, toward: target.key)
            )
            if reach.shoots {
                let range = NPCArcheryRange(
                    style: owner.styleTuning(of: actor.key) ?? .neutral,
                    radius: actor.capsule.radius * actor.scale
                )
                inputs.archery = range
                // The machine closes to its striking distance, which is the reach less the slack.
                let slack = owner.behaviors[actor.key]?.settings.reachSlack
                    ?? CombatBehaviorSettings.standard.reachSlack
                inputs.reach = range.preferred + slack
            }
            inputs.facingError = facingError(of: actor, toward: target.feet)
            inputs.flies = world.combatFlies(actor.key)
            inputs.canChain = reach.weapon.handType.isOneHandedMelee
            inputs.weaponOut = owner.drawState(of: actor.key) == .drawn
                && world.combatGraphIsAttackReady(actor.key) ?? true
            return inputs
        }
    }
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
