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
    func facing(
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
                let picked = target(of: actor, player: player, choices: choices, world: world)
                owner.drive(
                    actor: actor, influence: influence,
                    target: repick(actor.key, picked: picked, choices: choices, player: player),
                    world: world
                )
            }
            owner.keepTargetPicks(of: driven.map(\.key))
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

        /// The target is picked again at once when it is no longer valid, else 1 second after
        /// the last pick, or 3 seconds after a pick that changed it
        /// (docs/engine/combat.md#npc-foes).
        fileprivate func repick(
            _ key: ReferenceKey, picked: MeleeTarget, choices: TargetChoices, player: MeleeAttacker
        ) -> MeleeTarget {
            let you = MeleeTarget(key: player.key, feet: player.feet, capsule: player.capsule)
            let foe = choices.foe.map { [$0] } ?? []
            let valid = !choices.fightsPlayer && !foe.isEmpty ? foe : [you] + choices.allies + foe
            let step = CombatLoopRuntime.fixedStepSeconds
            if
                var kept = owner.targetPicks[key], kept.wait - step > 0,
                !owner.isForcedOntoPlayer(key),
                let current = valid.first(where: { $0.key == kept.target })
            {
                kept.wait -= step
                owner.targetPicks[key] = kept
                return current
            }
            let changed = owner.targetPicks[key].map { $0.target != picked.key } ?? false
            owner.targetPicks[key] = CombatTargetPick(
                target: picked.key,
                wait: changed ? CombatTargetPick.changedSeconds : CombatTargetPick.keptSeconds
            )
            return picked
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
                    weapon: reach.weapon, settings: settings, actorScale: actor.scale,
                    unarmedReach: actor.unarmedReach
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
            inputs.targetIsStaggered = owner.behaviors[target.key]?.phase == .staggered
            inputs.actorRadius = actor.capsule.radius * actor.scale
            inputs.targetVelocity = owner.targetTracks[target.key]?.velocity ?? .zero
            let player = world.combatPlayer
            inputs.targetIsPlayer = target.key == player.key
            inputs.targetYaw = inputs.targetIsPlayer ? player.facing
                : world.combatActor(key: target.key)?.yaw
            return inputs
        }
    }
}

extension CombatLoopRuntime {
    /// Forgets the target picks of actors that are no longer driven.
    func keepTargetPicks(of driven: [ReferenceKey]) {
        let kept = Set(driven)
        targetPicks = targetPicks.filter { kept.contains($0.key) }
    }
}
