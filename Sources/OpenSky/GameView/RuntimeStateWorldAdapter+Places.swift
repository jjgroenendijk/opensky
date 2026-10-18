// The place seam of the live condition context: deaths, the player's regions, and
// which map markers show.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

extension RuntimeStateWorldAdapter {
    func placeResolution(references: RuntimeReferenceIndex) -> PlaceConditionResolution {
        let deaths = deathView()
        return PlaceConditionResolution(
            deadReferences: deaths.dead,
            deadCounts: deaths.counts,
            playerRegions: game.streamer.map { Set($0.playerRegions) },
            visibleMarkers: visibleMarkers(in: references)
        )
    }

    private func deathView() -> DeathView {
        let worldState = game.worldState
        let key = DeathViewKey(
            store: ObjectIdentifier(worldState),
            streamer: game.streamer.map(ObjectIdentifier.init),
            cells: game.streamer?.residentCellLocations,
            deaths: worldState.revision(of: [.death])
        )
        return conditionCaches.deaths.value(for: key) {
            var view = DeathView()
            for key in worldState.sortedDirtyKeys() {
                guard worldState.component(ActorDeathState.self, for: key)?.isDead == true else {
                    continue
                }
                view.dead.insert(key)
                let entry = game.streamer?.referenceEntry(key: key)
                    ?? game.streamer?.pluginPlacement(of: key)?.entry
                if let base = entry?.placedActor?.base {
                    view.counts[base, default: 0] += 1
                }
            }
            return view
        }
    }

    private func visibleMarkers(in references: RuntimeReferenceIndex) -> Set<ReferenceKey> {
        let worldState = game.worldState
        let key = MarkerViewKey(
            store: ObjectIdentifier(worldState),
            markers: worldState.revision(of: [.mapMarker]),
            references: references.sortedKeys()
        )
        return conditionCaches.markers.value(for: key) {
            var markers: Set<ReferenceKey> = []
            for entry in references.sortedEntries() {
                guard let record = entry.placedReference?.mapMarker else { continue }
                let state = worldState.component(MapMarkerState.self, for: entry.key)
                    ?? MapMarkerState(record: record)
                if state.isVisible {
                    markers.insert(entry.key)
                }
            }
            return markers
        }
    }
}
