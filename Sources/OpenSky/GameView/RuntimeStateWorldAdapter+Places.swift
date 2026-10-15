// The place seam of the live condition context: deaths, the player's regions, and
// which map markers show.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension RuntimeStateWorldAdapter {
    func placeResolution(references: RuntimeReferenceIndex) -> PlaceConditionResolution {
        var dead: Set<ReferenceKey> = []
        var counts: [FormID: Int] = [:]
        let worldState = game.worldState
        for key in worldState.sortedDirtyKeys() {
            guard worldState.component(ActorDeathState.self, for: key)?.isDead == true else {
                continue
            }
            dead.insert(key)
            let entry = game.streamer?.referenceEntry(key: key)
                ?? game.streamer?.pluginPlacement(of: key)?.entry
            if let base = entry?.placedActor?.base {
                counts[base, default: 0] += 1
            }
        }
        var markers: Set<ReferenceKey> = []
        for entry in references.sortedEntries() {
            guard let record = entry.placedReference?.mapMarker else { continue }
            let state = worldState.component(MapMarkerState.self, for: entry.key)
                ?? MapMarkerState(record: record)
            if state.isVisible {
                markers.insert(entry.key)
            }
        }
        return PlaceConditionResolution(
            deadReferences: dead,
            deadCounts: counts,
            playerRegions: game.streamer.map { Set($0.playerRegions) },
            visibleMarkers: markers
        )
    }
}
