// The opponents' half of one fixed step: each engaged actor's machine, movement, clip,
// and blow, landed through the player's own hit path. Engaged means living, not the
// player or its ally, and hostile or pushed in. Nearest first, cut at
// `maximumEngagedActors` (the mover's crowd cap); the cut is counted. Allies take what
// is left of the cap. See docs/engine/combat-behavior.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import simd

extension CombatLoopRuntime {
    /// Advances every engaged actor by one fixed step and acts on what each did.
    /// - Returns: the hostility read for each living actor, so the step asks once.
    @discardableResult
    public func driveBehaviors(world: any CombatLoopWorld) -> [ReferenceKey: ActorHostility] {
        let actors = world.combatActors()
        settleRoster(actors)
        let player = world.combatPlayer
        var hostility: [ReferenceKey: ActorHostility] = [:]
        var influences: [ReferenceKey: ActorMagicInfluence] = [:]
        var ignoring: Set<ReferenceKey> = []
        for actor in actors where !actor.isDead && actor.key != player.key {
            hostility[actor.key] = world.combatHostility(of: actor.key)
            influences[actor.key] = world.combatInfluence(of: actor.key)
            if world.combatIgnoredByPackage(actor.key) {
                ignoring.insert(actor.key)
            }
        }
        for actor in actors
            where influences[actor.key]?.refusesCombat == true || ignoring.contains(actor.key)
        {
            holdStill(actor.key, world: world)
        }
        recruitAssistants(
            among: actors, hostility: &hostility, ignoring: ignoring, world: world
        )
        let candidates = actors
            .filter { actor in
                guard let stance = hostility[actor.key], commanders[actor.key] != player.key
                else { return false }
                let influence = influences[actor.key] ?? .none
                guard !influence.refusesCombat, !ignoring.contains(actor.key) else {
                    return false
                }
                return stance == .hostile || influence.isFrenzied
                    || engagesWithoutPerceiving(actor.key)
            }
            .sorted {
                (simd_distance($0.feet, player.feet), $0.key)
                    < (simd_distance($1.feet, player.feet), $1.key)
            }
        noteCrowdedOut(max(0, candidates.count - Self.maximumEngagedActors))
        let allies = Self.meleeTargets(
            actors.filter { !$0.isDead && commanders[$0.key] == player.key }
        )
        let driven = candidates.prefix(Self.maximumEngagedActors)
        for actor in driven {
            drive(
                actor: actor,
                influence: influences[actor.key] ?? .none,
                target: target(of: actor, player: player, allies: allies, world: world),
                world: world
            )
        }
        driveAllies(
            among: actors,
            foes: Self.meleeTargets(driven.filter { behaviors[$0.key]?.isEngaged == true }),
            budget: Self.maximumEngagedActors - driven.count,
            influences: influences, world: world
        )
        return hostility
    }

    /// Retires the machines of actors that left and parks those of the dead.
    private func settleRoster(_ actors: [CombatActorObservation]) {
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
    }

    private static func meleeTargets(
        _ actors: some Sequence<CombatActorObservation>
    ) -> [MeleeTarget] {
        actors.map { MeleeTarget(key: $0.key, feet: $0.feet, capsule: $0.capsule) }
    }

    /// A foe fights the nearest of the player and the player's allies it has seen. A
    /// script's `StartCombat` keeps it on the player.
    private func target(
        of actor: CombatActorObservation,
        player: MeleeAttacker,
        allies: [MeleeTarget],
        world: any CombatLoopWorld
    ) -> MeleeTarget {
        let you = MeleeTarget(key: player.key, feet: player.feet, capsule: player.capsule)
        guard !allies.isEmpty, !isForcedOntoPlayer(actor.key) else { return you }
        let seen = allies.filter {
            world.combatAwareness(of: actor.key, toward: $0.key).isDetected
        }
        return CombatAllyRule.nearest([you] + seen, to: actor.feet) ?? you
    }

    /// Calm "lowers the Aggression" and Paralysis stops all movement: an actor in a
    /// fight leaves it and stands where it is.
    private func holdStill(_ key: ReferenceKey, world: any CombatLoopWorld) {
        guard let machine = behaviors[key], machine.phase != .idle else { return }
        parkBehavior(of: key)
        world.stopCombatMovement(of: key)
    }

    /// One actor: build what it knows, step its machine, act on the answer. The
    /// target is the player or its ally for a foe, and a foe for an ally.
    func drive(
        actor: CombatActorObservation,
        influence: ActorMagicInfluence,
        target: MeleeTarget,
        world: any CombatLoopWorld
    ) {
        targets[actor.key] = target.key
        let weapon = world.combatWeapon(of: actor.key)
        let step = stepBehavior(of: actor.key, inputs: CombatBehaviorInputs(
            actorPosition: actor.feet,
            targetPosition: target.feet,
            awareness: world.combatAwareness(of: actor.key, toward: target.key),
            reach: MeleeSwing.reach(
                weapon: weapon, settings: settings, actorScale: actor.scale
            ),
            healthFraction: world.combatHealthFraction(of: actor.key),
            isTargetAlive: true,
            isForced: engagesWithoutPerceiving(actor.key),
            casting: world.combatCasting(of: actor.key),
            influence: influence,
            temperament: world.combatTemperament(of: actor.key, toward: target.key)
        ))
        if step.startedAttack {
            world.playCombatClip(.attack, on: actor.key)
            world.applyCombatSwingSpell(blow(by: actor.key, weapon: weapon), at: target.key)
        }
        resolveCast(step, actor: actor.key, world: world)
        if step.reachedContact, !influence.isEthereal {
            resolveContact(actor: actor, weapon: weapon, target: target, world: world)
        }
        if step.endedPursuit {
            world.resumeCombatPackage(for: actor.key)
        }
        if let command = step.command {
            route(command, actor: actor.key, world: world)
        }
    }

    /// The casting half of one step: only when to begin, release or cancel. The caster
    /// runtime spends magicka and delivery decides the target. A refused begin drops the
    /// charge, so the actor swings again next step.
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

    /// The contact step: sweep the actor's reach at its target and apply
    /// whatever it found.
    private func resolveContact(
        actor: CombatActorObservation,
        weapon: MeleeWeaponProfile,
        target: MeleeTarget,
        world: any CombatLoopWorld
    ) {
        let volume = MeleeSwing.volume(
            feet: actor.feet,
            capsule: actor.capsule,
            facing: facing(from: actor.feet, toward: target.feet, fallback: actor.facing),
            reach: MeleeSwing.reach(
                weapon: weapon, settings: settings, actorScale: actor.scale
            )
        )
        let hits = MeleeHitDetector.hits(swing: volume, targets: [target], attacker: actor.key)
        guard !hits.isEmpty else { return }
        apply(from: actor, weapon: weapon, to: target.key, world: world)
    }

    /// One landed blow: the pinned 15.4 damage formula, the health write, and,
    /// on the player, the hit reaction and the trace.
    private func apply(
        from actor: CombatActorObservation,
        weapon: MeleeWeaponProfile,
        to target: ReferenceKey,
        world: any CombatLoopWorld
    ) {
        let blow = blow(by: actor.key, weapon: weapon)
        let damage = MeleeDamage.resolve(
            weapon: weapon,
            block: world.combatBlock(of: target),
            settings: settings,
            bonusMultiplier: world.combatBlockMultiplier(of: target),
            strike: world.combatStrike(blow, on: target)
        )
        let landed = world.applyCombatDamage(damage.applied, to: target)
        if landed {
            world.applyCombatHitSpell(blow, on: target)
        }
        if damage.wasBlocked {
            world.applyCombatBlockStamina(damage, to: target)
        }
        // The reverse of the player's own swing dispatch: the target's scripts get
        // `OnHit` with this actor as `akAggressor`.
        world.reportScriptHit(ScriptHitEvent(
            target: target,
            aggressor: actor.key,
            source: weapon.weapon,
            isBlocked: damage.wasBlocked
        ))
        guard target == world.combatPlayer.key else { return }
        noteSkillUse(from: actor, weapon: weapon, damage: damage, landed: landed, world: world)
        if damage.wasBlocked {
            noteBlockRecoil(of: actor.key, blockedBy: target, world: world)
        }
        // The magnitude is written before the event so the recoil behavior
        // reads this blow's number rather than the previous one's, which is the
        // same write-then-raise order the melee runtime uses for a stagger.
        let played = damage.applied > 0
            && (raiseStagger(weapon: weapon, damage: damage, world: world)
                || raiseRecoil(magnitude: damage.applied, world: world))
        append(CombatIncomingHit(
            aggressor: actor.key,
            damage: damage,
            playedReaction: played,
            attackID: nextAttackID()
        ))
    }

    private func blow(by actor: ReferenceKey, weapon: MeleeWeaponProfile) -> CombatBlow {
        CombatBlow(
            attacker: actor,
            weapon: weapon.weapon,
            handType: weapon.handType,
            baseDamage: weapon.damage
        )
    }

    /// The reverse of the player's own swing report. NPC blows are plain swings, and
    /// progression decides who advances (the player only).
    private func noteSkillUse(
        from actor: CombatActorObservation,
        weapon: MeleeWeaponProfile,
        damage: MeleeDamageResult,
        landed: Bool,
        world: any CombatLoopWorld
    ) {
        let blow = MeleeSkillUseBlow(
            attacker: actor.key,
            target: world.combatPlayer.key,
            handType: weapon.handType,
            damage: damage,
            landed: landed
        )
        for use in MeleeSkillUses.events(for: blow, settings: skillUses) {
            world.reportSkillUse(use)
        }
    }

    /// Raises the census-named hit reaction on the player's graph, magnitude
    /// first.
    ///
    /// - Returns: whether the graph declared the event, which is the graph's own
    ///   answer rather than an assumption about it.
    /// An NPC blow staggers the player by `StaggerRule`, the player's mass included.
    private func raiseStagger(
        weapon: MeleeWeaponProfile, damage: MeleeDamageResult, world: any CombatLoopWorld
    ) -> Bool {
        var hit = StaggerHit(weaponStagger: weapon.stagger)
        hit.perkMultiplier = damage.strike.staggerMultiplier
        hit.wasBlocked = damage.wasBlocked
        hit.isPlayerTarget = true
        let magnitude = StaggerRule.magnitude(hit, settings: staggers)
        let roll = staggerRandom.percent()
        guard StaggerRule.staggers(magnitude: magnitude, roll: roll, settings: staggers)
        else { return false }
        world.writeCombatVariable(.real(magnitude), named: CombatGraphNames.staggerMagnitude)
        return world.raiseCombatEvent(CombatGraphNames.staggerStart, on: nil)
    }

    /// A swing the player blocked recoils its attacker by the player's Block skill.
    private func noteBlockRecoil(
        of attacker: ReferenceKey, blockedBy blocker: ReferenceKey, world: any CombatLoopWorld
    ) {
        let magnitude = StaggerRule.blockRecoil(
            blockerSkill: world.combatBlockSkill(of: blocker), settings: staggers
        )
        let roll = staggerRandom.percent()
        guard StaggerRule.staggers(magnitude: magnitude, roll: roll, settings: staggers)
        else { return }
        noteStagger(of: attacker)
    }

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
