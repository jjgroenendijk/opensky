// Map marker discovery and the marker list the map shows. Pure: positions and
// states in, changes out. Distances are the game settings measured from
// Skyrim.esm (docs/engine/world-map.md).

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMenusInterface
public import OpenSkyWorldInterface
import simd

nonisolated public enum MapMarkerChange: Equatable, Sendable {
    /// The player came close for the first time; the HUD names the place.
    case discovered(ReferenceKey, name: String)
}

nonisolated public enum MapMarkerRules {
    /// The opacity of a compass marker at or past the fade distance.
    static let compassMinimumOpacity: Float = 50

    /// The named markers the compass shows: a known one within `compassDistance`, and an
    /// unknown one within `visibleDistance`. Each fades from 100 at the player to the
    /// minimum at `fadeStartDistance`, by the squared distance.
    public static func compassLocations(
        _ sites: [MapMarkerSite], player: SIMD3<Float>, settings: MenuMapSettings
    ) -> [CompassLocation] {
        sites.compactMap { site in
            guard !site.name.isEmpty else { return nil }
            let known = site.state.isVisible || site.state.isDiscovered
            let reach = known ? settings.compassDistance : settings.visibleDistance
            let squared = simd_distance_squared(site.position, player)
            guard squared <= reach * reach else { return nil }
            return CompassLocation(
                position: site.position,
                isKnown: known,
                opacityPercent: compassOpacity(squaredDistance: squared, settings: settings)
            )
        }
    }

    static func compassOpacity(squaredDistance: Float, settings: MenuMapSettings) -> Float {
        let start = settings.fadeStartDistance * settings.fadeStartDistance
        let share = start > 0 ? min(squaredDistance / start, 1) : 1
        return compassMinimumOpacity + (100 - compassMinimumOpacity) * (1 - share)
    }

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
    static func shown(
        _ sites: [MapMarkerSite],
        around point: SIMD3<Float>
    ) -> [MapMarkerSite] {
        sites.filter(\.state.isVisible).sorted {
            simd_distance_squared($0.position, point) < simd_distance_squared($1.position, point)
        }
    }
}
