// Quest markers: the targets of the tracked quests' open objectives, on the HUD
// compass and on the map. See docs/engine/world-map.md, quest targets.

import Foundation
import OpenSkyFormatsESM
import simd

extension MapMenuCoordinator {
    /// Each refresh evaluates every target's conditions, so it runs every few frames.
    static let questMarkerFrames = 15

    func refreshQuestMarkersIfDue() {
        questMarkerFrame += 1
        guard questMarkerFrame >= Self.questMarkerFrames else { return }
        questMarkerFrame = 0
        refreshQuestMarkers()
    }

    public func refreshQuestMarkers() {
        guard let world else { return }
        questMarkers = world.questTargets
        world.showQuestMarkers(questMarkers.map(\.position))
    }

    /// Opens the map on the first target of `objective`, or of the first tracked
    /// quest when no objective is named. False when there is no such target.
    @discardableResult
    public func showQuestTarget(quest: FormID? = nil, objective: UInt16? = nil) -> Bool {
        refreshQuestMarkers()
        let target = questMarkers.first { marker in
            (quest == nil || marker.quest == quest)
                && (objective == nil || marker.objective == objective)
        }
        guard let target else {
            lastResultText = "No quest target to show"
            return false
        }
        if isOpen {
            close()
        }
        let opened = open(.world, focus: target.position)
        lastResultText = opened ? "Showing \(target.text)" : "Map did not open"
        return opened
    }

    /// One line per target: its text and where it stands.
    var questMarkerLines: [String] {
        questMarkers.map { marker in
            let place = marker.position
            return "\(marker.text) at \(Int(place.x)), \(Int(place.y))"
        }
    }
}
