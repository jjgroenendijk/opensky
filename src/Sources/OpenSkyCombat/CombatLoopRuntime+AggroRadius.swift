// The aggro radius: an actor that is not hostile warns a stranger near it and attacks
// one that comes nearer or stays. docs/engine/aggro-radius.md.

import Foundation
import OpenSkyActorsInterface
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPerceptionInterface
import simd

extension CombatLoopRuntime {
    public func aggroZone(of key: ReferenceKey) -> AggroZone? {
        aggroWatches[key]?.zone
    }

    /// Warns or provokes each actor whose aggro radius the player, a teammate of the
    /// player, or a stranger NPC is inside. An actor whose target left sheathes again.
    func watchAggroRadii(
        _ actors: [CombatActorObservation],
        hostility: inout [ReferenceKey: ActorHostility],
        ignoring: Set<ReferenceKey>,
        world: any CombatLoopWorld
    ) {
        AggroWatches(owner: self).watchAggroRadii(
            actors,
            hostility: &hostility,
            ignoring: ignoring,
            world: world
        )
    }
}

/// Someone a warning actor watches: the player, a teammate of the player, or an NPC.
struct AggroTarget {
    let key: ReferenceKey
    let feet: SIMD3<Float>
    /// The player or a teammate: the reaction test is run against the player.
    var isPlayerSide = true
}

extension CombatLoopRuntime {
    /// After its target leaves, a warning actor keeps its head on it this long.
    static let aggroLookSeconds: Float = 5

    /// Watches the aggro radii and says the warning lines.
    struct AggroWatches {
        let owner: CombatLoopRuntime

        func watchAggroRadii(
            _ actors: [CombatActorObservation],
            hostility: inout [ReferenceKey: ActorHostility],
            ignoring: Set<ReferenceKey>,
            world: any CombatLoopWorld
        ) {
            let player = world.combatPlayer
            var targets = [AggroTarget(key: player.key, feet: player.feet)]
            for actor in actors where !actor.isDead {
                let playerSide = owner.commanders[actor.key] == player.key
                targets.append(AggroTarget(
                    key: actor.key,
                    feet: actor.feet,
                    isPlayerSide: playerSide
                ))
            }
            var live: [ReferenceKey: AggroWatch] = [:]
            for actor in actors where hostility[actor.key] == .neutral
                && owner.commanders[actor.key] != player.key && !ignoring.contains(actor.key)
                && !actor.isDead
            {
                guard let seen = aggroTarget(of: actor, among: targets, world: world)
                else { continue }
                var watch = owner.aggroWatches[actor.key] ?? AggroWatch()
                if watch.target != seen.target.key {
                    watch = AggroWatch()
                    watch.target = seen.target.key
                    world.raiseCombatEvent(AggroRadiusRule.drawEvent, on: actor.key)
                }
                let step = AggroRadiusRule.advance(
                    watch,
                    zone: seen.zone,
                    by: CombatLoopRuntime.fixedStepSeconds
                )
                live[actor.key] = step.watch
                if step.outcome == .attacks {
                    attack(seen.target, by: actor.key, hostility: &hostility)
                    continue
                }
                world.stopCombatMovement(of: actor.key)
                world.turnCombatActor(
                    actor.key,
                    toward: aimPoint(of: actor, at: seen.target, world: world)
                )
                world.lookCombatActor(actor.key, at: seen.target.key, seconds: nil)
                if step.outcome == .warns {
                    sayAggroLine(of: actor, to: seen.target, world: world)
                }
            }
            for (key, watch) in owner.aggroWatches
                where live[key] == nil && hostility[key] == .neutral
            {
                world.raiseCombatEvent(AggroRadiusRule.sheatheEvent, on: key)
                world.lookCombatActor(
                    key,
                    at: watch.target,
                    seconds: CombatLoopRuntime.aggroLookSeconds
                )
            }
            owner.aggroWatches = live
        }

        /// The player's side provokes the actor; an NPC target becomes its foe.
        private func attack(
            _ target: AggroTarget, by key: ReferenceKey,
            hostility: inout [ReferenceKey: ActorHostility]
        ) {
            guard target.isPlayerSide else {
                owner.aggroFoePairs.insert(CombatFoePair(observer: key, target: target.key))
                owner.foePairs.insert(CombatFoePair(observer: key, target: target.key))
                return
            }
            if owner.provoke(key) {
                hostility[key] = .hostile
            }
        }

        /// A bow or crossbow turns the body to where its arrow would meet the target;
        /// a staff, a melee weapon, or a spell faces the target itself.
        func aimPoint(
            of actor: CombatActorObservation, at target: AggroTarget, world: any CombatLoopWorld
        ) -> SIMD3<Float> {
            let hand = world.combatWeapon(of: actor.key).handType
            guard hand == .bow || hand == .crossbow else { return target.feet }
            return world.combatAimPoint(
                of: actor, at: target.feet,
                velocity: owner.targetTracks[target.key]?.velocity ?? .zero
            ) ?? target.feet
        }

        /// The line needs the actor to face its target and to detect it.
        func sayAggroLine(
            of actor: CombatActorObservation, to target: AggroTarget, world: any CombatLoopWorld
        ) {
            guard
                AggroRadiusRule.faces(target.feet, from: actor.feet, yaw: actor.yaw),
                world.combatAwareness(of: actor.key, toward: target.key).state == .detected
            else { return }
            world.sayCombatWarning(by: actor.key, to: target.key)
        }

        /// The nearest target the actor has noticed inside one of its distances, with its
        /// zone. Nil when the actor has no radius. A target qualifies when the actor's
        /// reaction to it, or to the player for the player's side, is Neutral or Enemy.
        func aggroTarget(
            of actor: CombatActorObservation, among targets: [AggroTarget],
            world: any CombatLoopWorld
        ) -> (target: AggroTarget, zone: AggroZone)? {
            guard let radius = world.combatAggroRadius(of: actor.key) else { return nil }
            let playerReaction = world.combatReaction(toPlayerOf: actor.key) ?? .neutral
            let noticed = targets.filter { target in
                target.key != actor.key
                    && AggroRadiusRule.zone(
                        distance: simd_distance(actor.feet, target.feet), radius: radius
                    ) != .outside
                    && qualifies(
                        target,
                        for: actor.key,
                        playerReaction: playerReaction,
                        world: world
                    )
                    && world.combatAwareness(of: actor.key, toward: target.key).state != .unaware
            }
            guard
                let nearest = noticed.min(by: {
                    simd_distance_squared(actor.feet, $0.feet)
                        < simd_distance_squared(actor.feet, $1.feet)
                })
            else { return nil }
            let zone = AggroRadiusRule.zone(
                distance: simd_distance(actor.feet, nearest.feet), radius: radius
            )
            return (nearest, zone)
        }

        /// An NPC target needs a known reaction, and is skipped once the actor fights it.
        private func qualifies(
            _ target: AggroTarget, for key: ReferenceKey, playerReaction: ActorReaction,
            world: any CombatLoopWorld
        ) -> Bool {
            guard !target.isPlayerSide else { return playerReaction >= .neutral }
            guard !owner.foePairs.contains(CombatFoePair(observer: key, target: target.key))
            else { return false }
            return (world.combatReaction(of: key, toward: target.key) ?? .ally) >= .neutral
        }
    }
}
