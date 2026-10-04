// Map marker discovery and the marker list the map shows. Pure: positions and
// states in, changes out. Distances are the game settings measured from
// Skyrim.esm (docs/engine/world-map.md).

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import simd

/// One marker the map knows: where it is and its effective state.
nonisolated public struct MapMarkerSite: Equatable, Sendable {
    public let key: ReferenceKey
    public let name: String
    public let position: SIMD3<Float>
    public var state: MapMarkerState

    public init(
        key: ReferenceKey,
        name: String,
        position: SIMD3<Float>,
        state: MapMarkerState
    ) {
        self.key = key
        self.name = name
        self.position = position
        self.state = state
    }
}

nonisolated public enum MapMarkerChange: Equatable, Sendable {
    /// The player came close for the first time; the HUD names the place.
    case discovered(ReferenceKey, name: String)
}

nonisolated public enum MapMarkerRules {
    /// Discovers each marker within the reveal distance of `player`. A discovered
    /// marker is also visible and a travel target.
    public static func discover(
        _ sites: inout [MapMarkerSite], player: SIMD3<Float>, settings: MenuMapSettings
    ) -> [MapMarkerChange] {
        var changes: [MapMarkerChange] = []
        for index in sites.indices where !sites[index].state.isDiscovered {
            guard simd_distance(sites[index].position, player) <= settings.revealDistance else {
                continue
            }
            sites[index].state = MapMarkerState(
                isVisible: true,
                isDiscovered: true,
                canTravelTo: true
            )
            changes.append(.discovered(sites[index].key, name: sites[index].name))
        }
        return changes
    }

    /// `AddToMap(abAllowFastTravel)`: shows the marker; travel only when asked.
    /// Adding never takes travel away.
    public static func addToMap(_ state: MapMarkerState, allowFastTravel: Bool) -> MapMarkerState {
        MapMarkerState(
            isVisible: true, isDiscovered: state.isDiscovered,
            canTravelTo: state.canTravelTo || allowFastTravel
        )
    }

    /// The markers the world map draws: visible ones, nearest first.
    public static func shown(
        _ sites: [MapMarkerSite],
        around point: SIMD3<Float>
    ) -> [MapMarkerSite] {
        sites.filter(\.state.isVisible).sorted {
            simd_distance_squared($0.position, point) < simd_distance_squared($1.position, point)
        }
    }
}
