// The speeds an NPC moves at this step: its movement type, then its speed multiplier, worn
// armour, drawn weapon, and race rates. See docs/engine/navigation.md#npc-path-following.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkySessionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Reads one NPC's movement speed inputs from the session.
struct AINPCSpeedReads {
    let hosts: any AIWorldHosts
    let settings: MovementSpeedSettings

    func speeds(of actor: ReferenceKey) -> ActorMovementSpeeds {
        var result = ActorMovementSpeeds(
            speeds: AIRecordReads(game: hosts).movementSpeeds(of: actor)
        )
        let holder = hosts.actorWorld.actorValueHolder(for: actor)
        let speedMult = holder.flatMap { holder in
            hosts.actorValues.runtime?.value(at: ActorValueIndex.speedMult, on: holder)
        }
        result.multiplier = speedMult.map(ActorMovementSpeeds.multiplier(speedMult:)) ?? 1
        let fighting = (hosts.combat.loop?.activity(of: actor) ?? .notFighting) != .notFighting
        let worn = hosts.streamer.inventoryHolder(of: actor)
            .map { hosts.inventory.armourWeights.wornArmourWeight(of: $0) } ?? 0
        result.runShare = settings.encumbranceFactor(weight: worn, weaponDrawn: fighting)
        return result
    }
}
