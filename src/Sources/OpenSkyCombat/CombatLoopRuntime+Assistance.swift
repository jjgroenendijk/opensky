// Assistance: a calm actor near an ally in a fight joins it on the ally's side
// (<https://ck.uesp.net/wiki/AI_Data_Tab>, "Assistance").

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import simd

extension CombatLoopRuntime {
    /// How far an actor looks for an ally in a fight. OpenSky's value; the wiki names
    /// no range.
    static let assistRadius: Float = 2048

    /// Only living, calm actors within `assistRadius` of an engaged one are asked, and
    /// only about an ally they detect. Perception tracks those pairs for the next step.
    func recruitAssistants(
        among actors: [CombatActorObservation],
        hostility: inout [ReferenceKey: ActorHostility],
        ignoring: Set<ReferenceKey>,
        world: any CombatLoopWorld
    ) {
        allyWatchPairs = []
        let fighting = actors.filter { !$0.isDead && behaviors[$0.key]?.isEngaged == true }
        guard !fighting.isEmpty else { return }
        let player = world.combatPlayer.key
        for actor in actors {
            guard
                !actor.isDead, actor.key != player, commanders[actor.key] == nil,
                hostility[actor.key] == .neutral,
                !ignoring.contains(actor.key), behaviors[actor.key]?.isEngaged != true
            else { continue }
            let near = fighting.filter { other in
                other.key != actor.key
                    && simd_distance(other.feet, actor.feet) <= Self.assistRadius
            }
            for other in near {
                allyWatchPairs.insert(CombatFoePair(observer: actor.key, target: other.key))
            }
            let ally = near.first { other in
                world.combatAwareness(of: actor.key, toward: other.key).isDetected
                    && helps(actor.key, other.key, world: world)
            }
            guard let ally else { continue }
            assist(actor.key, ally: ally.key, hostility: &hostility, world: world)
        }
    }

    private func assist(
        _ helper: ReferenceKey, ally: ReferenceKey,
        hostility: inout [ReferenceKey: ActorHostility], world: any CombatLoopWorld
    ) {
        if fightsPlayerSide(ally) {
            joinFight(helper, assisting: ally)
            hostility[helper] = .hostile
        } else if
            let foe = targets[ally], npcAssists[helper] == nil,
            !helps(helper, foe, world: world)
        {
            // The ally fights an NPC: the helper takes that NPC on, not the player.
            // One that would help that NPC too stays out.
            npcAssists[helper] = foe
            joinedGroups[helper] = ally
            record(.assisted(helper, ally: ally))
        }
    }
}
