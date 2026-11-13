// Spawned and levelled actors, and the floors they stand on.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyTerrain
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

nonisolated extension CellSceneBuilder.CellActorSpawnBuilder {
    /// Records the cell's zone for its containers, and each actor's zone (its own
    /// `XEZN`, else the cell's) and `XLCM` by reference and by base, before its
    /// template chain rolls.
    nonisolated func recordLeveledPlacements(
        _ collected: [CollectedActor], location: CellSceneLocation, zone: FormID?
    ) {
        let zones = owner.caches
            .encounterZones ?? EncounterZoneStore(plugins: owner.loadOrderPlugins)
        owner.caches.encounterZones = zones
        let cellZone = zone.flatMap { zones.resolve($0, fromPlugin: owner.pluginName)?.zone }
        owner.leveling.placements.record(cell: location, zone: cellZone)
        for collectedActor in collected {
            let actor = collectedActor.actor
            let own = actor.details.links["XEZN"].flatMap {
                zones.resolve($0, fromPlugin: FormIDResolver.loadOrderSpaceName)?.zone
            }
            let placement = LeveledActorPlacement(
                zone: own ?? cellZone,
                difficulty: LeveledActorDifficulty(levelModifier: actor.details.levelModifier)
            )
            owner.leveling.placements.record(actor: actor.base, placement)
            let key = collectedActor.spawnKey
                ?? ReferenceKey.resolve(actor.formID, using: owner.formIDResolver)
            if let key {
                owner.leveling.placements.record(reference: key, placement)
            }
        }
    }
}
