// The aggro radius: an actor that is not hostile warns a stranger near it and attacks
// one that comes nearer or stays. docs/engine/combat-behavior.md#aggro-radius.

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

    /// Warns or provokes each actor whose aggro radius the player or a teammate of the
    /// player is inside. An actor whose target left sheathes again.
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

/// The player or a teammate of the player, as a warning actor sees it.
struct AggroTarget {
    let key: ReferenceKey
    let feet: SIMD3<Float>
}

extension CombatLoopRuntime {
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
            targets += actors.filter { owner.commanders[$0.key] == player.key && !$0.isDead }
                .map { AggroTarget(key: $0.key, feet: $0.feet) }
            var live: [ReferenceKey: AggroWatch] = [:]
            for actor in actors where hostility[actor.key] == .neutral
                && owner.commanders[actor.key] != player.key && !ignoring.contains(actor.key)
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
                    if owner.provoke(actor.key) {
                        hostility[actor.key] = .hostile
                    }
                    continue
                }
                world.stopCombatMovement(of: actor.key)
                world.turnCombatActor(actor.key, toward: seen.target.feet)
                if step.outcome == .warns {
                    sayAggroLine(of: actor, to: seen.target, world: world)
                }
            }
            for key in owner.aggroWatches.keys
                where live[key] == nil && hostility[key] == .neutral
            {
                world.raiseCombatEvent(AggroRadiusRule.sheatheEvent, on: key)
            }
            owner.aggroWatches = live
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
        /// zone. Nil when the actor has no radius or is a friend or an ally of the player.
        func aggroTarget(
            of actor: CombatActorObservation, among targets: [AggroTarget],
            world: any CombatLoopWorld
        ) -> (target: AggroTarget, zone: AggroZone)? {
            guard
                let radius = world.combatAggroRadius(of: actor.key),
                (world.combatReaction(toPlayerOf: actor.key) ?? .neutral) >= .neutral
            else { return nil }
            let noticed = targets.filter { target in
                AggroRadiusRule.zone(
                    distance: simd_distance(actor.feet, target.feet), radius: radius
                ) != .outside
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
    }
}
