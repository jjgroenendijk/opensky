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

    /// Warns or provokes each actor whose aggro radius the player is inside.
    func watchAggroRadii(
        _ actors: [CombatActorObservation],
        hostility: inout [ReferenceKey: ActorHostility],
        ignoring: Set<ReferenceKey>,
        world: any CombatLoopWorld
    ) {
        let player = world.combatPlayer
        var live: [ReferenceKey: AggroWatch] = [:]
        for actor in actors where hostility[actor.key] == .neutral
            && commanders[actor.key] != player.key && !ignoring.contains(actor.key)
        {
            guard let zone = aggroZone(of: actor, player: player, world: world) else { continue }
            let (watch, attacks) = AggroRadiusRule.advance(
                aggroWatches[actor.key] ?? AggroWatch(), zone: zone, by: Self.fixedStepSeconds
            )
            live[actor.key] = watch
            if attacks {
                if provoke(actor.key) {
                    hostility[actor.key] = .hostile
                }
            } else {
                world.stopCombatMovement(of: actor.key)
                world.turnCombatActor(actor.key, toward: player.feet)
            }
        }
        aggroWatches = live
    }

    /// The zone the player stands in, or nil when the actor has no radius, is a friend
    /// or an ally, has not noticed the player, or the player is outside.
    private func aggroZone(
        of actor: CombatActorObservation, player: MeleeAttacker,
        world: any CombatLoopWorld
    ) -> AggroZone? {
        guard
            let radius = world.combatAggroRadius(of: actor.key),
            (world.combatReaction(toPlayerOf: actor.key) ?? .neutral) >= .neutral
        else { return nil }
        let zone = AggroRadiusRule.zone(
            distance: simd_distance(actor.feet, player.feet), radius: radius
        )
        guard
            zone != .outside,
            world.combatAwareness(of: actor.key, toward: player.key).state != .unaware
        else { return nil }
        return zone
    }
}
