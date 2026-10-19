// Assistance: a calm actor near an ally that fights the player joins the fight
// (<https://ck.uesp.net/wiki/AI_Data_Tab>, "Assistance").

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import simd

extension CombatLoopRuntime {
    /// How far an actor looks for an ally in a fight. OpenSky's value; the wiki names
    /// no range.
    public static let assistRadius: Float = 2048

    /// Only living, calm actors within `assistRadius` of an engaged one are asked, so
    /// the faction check runs for few pairs.
    func recruitAssistants(
        among actors: [CombatActorObservation],
        hostility: inout [ReferenceKey: ActorHostility],
        ignoring: Set<ReferenceKey>,
        world: any CombatLoopWorld
    ) {
        let fighting = actors.filter { !$0.isDead && behaviors[$0.key]?.isEngaged == true }
        guard !fighting.isEmpty else { return }
        let player = world.combatPlayer.key
        for actor in actors {
            guard
                !actor.isDead, actor.key != player, hostility[actor.key] == .neutral,
                !ignoring.contains(actor.key), behaviors[actor.key]?.isEngaged != true
            else { continue }
            let ally = fighting.first { other in
                other.key != actor.key
                    && simd_distance(other.feet, actor.feet) <= Self.assistRadius
                    && world.combatAssists(actor.key, ally: other.key)
            }
            guard let ally else { continue }
            joinFight(actor.key, assisting: ally.key)
            hostility[actor.key] = .hostile
        }
    }
}
