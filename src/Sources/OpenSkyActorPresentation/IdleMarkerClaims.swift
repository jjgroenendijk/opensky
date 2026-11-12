// The idle markers near the player, and which sandboxing actor walks to which.
// See docs/engine/idle-runtime.md.

import Foundation
import OpenSkyBehavior
import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRuntimeState
import OpenSkyWorldConditionFunctions
import OpenSkyWorldInterface
import simd

/// The marker part of `IdleCoordinator`. It holds the markers and the claims'
/// memory; the sessions it fills stay with the coordinator.
final class IdleMarkerClaims {
    private(set) var markers: [IdleMarkerPlacement] = []
    private var refreshAt: Float = 0
    /// The marker each sandboxing actor last left, which it does not take again at once.
    var previous: [ReferenceKey: IdleMarkerPlacement] = [:]
    /// Markers an actor could not path to, so it does not retry every frame.
    private var unreachable: [ReferenceKey: Set<ReferenceKey>] = [:]

    /// Reads the placed markers again once a second, or after the clock went back.
    func refresh(now: Float, store: IdleStore, placements: () -> [IdleReferencePlacement]?) {
        guard now >= refreshAt || now < refreshAt - 10 else { return }
        markers = (placements() ?? []).compactMap { placement in
            store.markers.resolve(placement.base, fromPlugin: placement.plugin).map {
                IdleMarkerPlacement(
                    reference: placement.reference,
                    marker: $0,
                    position: placement.position,
                    heading: placement.heading
                )
            }
        }
        .sorted { $0.reference < $1.reference }
        refreshAt = now + 1
    }

    /// Sends each free sandboxing actor to the nearest free marker it can reach.
    func claim(
        actors: [ReferenceKey: IdleActorPresence],
        sessions: inout [ReferenceKey: IdleCoordinator.Session],
        world: any IdleWorld
    ) {
        var claimed = Set(sessions.values.compactMap { $0.marker?.reference })
        for key in actors.keys.sorted() {
            guard
                let actor = actors[key], sessions[key]?.marker == nil, !actor.isDead,
                IdleCore.usesMarkers(actor.procedure), actor.area?.allowsMarkers != false
            else { continue }
            let last = previous[key]
            var area = actor.area
            area?.previous = last?.position
            guard
                let marker = IdleCore.nearestFreeMarker(
                    to: actor.feet, among: markers, claimed: claimed,
                    excluded: (unreachable[key] ?? []).union(last.map { [$0.reference] } ?? []),
                    area: area
                )
            else { continue }
            let arrived = simd_distance(actor.feet, marker.position) <= IdleCore.arrivalRadius
            if !arrived, world.moveActor(key, to: marker.position) != .started {
                unreachable[key, default: []].insert(marker.reference)
                continue
            }
            claimed.insert(marker.reference)
            previous[key] = nil
            var session = sessions[key] ?? IdleCoordinator.Session()
            session.marker = marker
            session.arrived = arrived
            session.faced = false
            sessions[key] = session
        }
    }
}
