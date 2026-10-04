// Runtime state of map markers and of the local map fog. The marker record's
// flags give the start state; a script or the player changes it, and saves keep
// it. See docs/engine/world-map.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One marker's state where it differs from its record.
nonisolated public struct MapMarkerState: WorldStateComponent, Sendable {
    /// Shown on the world map.
    public var isVisible: Bool
    /// The player came close; the map then shows its full icon.
    public var isDiscovered: Bool
    public var canTravelTo: Bool

    public static var componentKind: WorldStateComponentKind {
        .mapMarker
    }

    public init(isVisible: Bool, isDiscovered: Bool, canTravelTo: Bool) {
        self.isVisible = isVisible
        self.isDiscovered = isDiscovered
        self.canTravelTo = canTravelTo
    }

    /// The start state from the REFR `FNAM` flags. A marker with the travel flag
    /// set in the plugin is a place the player starts out knowing.
    public init(record: MapMarker) {
        self.init(
            isVisible: record.isVisible, isDiscovered: record.isVisible && record.canTravelTo,
            canTravelTo: record.canTravelTo
        )
    }
}

/// Explored parts of each cell, for the local map fog. Each cell is an 8 by 8 grid,
/// one bit per square, row by row from the south-west corner.
nonisolated public struct LocalMapFogState: WorldStateComponent, Sendable {
    public static let gridSide = 8

    public var explored: [CellSceneLocation: UInt64]

    public static var componentKind: WorldStateComponentKind {
        .localMapFog
    }

    public init(explored: [CellSceneLocation: UInt64] = [:]) {
        self.explored = explored
    }

    /// Marks every square within `radius` squares of a square; true when anything changed.
    @discardableResult
    public mutating func explore(
        _ cell: CellSceneLocation, column: Int, row: Int, radius: Int = 1
    ) -> Bool {
        var mask = explored[cell] ?? 0
        let before = mask
        for dy in -radius ... radius {
            for dx in -radius ... radius where dx * dx + dy * dy <= radius * radius {
                if let bit = Self.bit(column: column + dx, row: row + dy) {
                    mask |= bit
                }
            }
        }
        explored[cell] = mask
        return mask != before
    }

    /// Squares explored out of all squares of `cell`.
    public func exploredCount(_ cell: CellSceneLocation) -> Int {
        (explored[cell] ?? 0).nonzeroBitCount
    }

    static func bit(column: Int, row: Int) -> UInt64? {
        guard (0 ..< gridSide).contains(column), (0 ..< gridSide).contains(row) else { return nil }
        return 1 << UInt64(row * gridSide + column)
    }
}

nonisolated extension WorldStateComponentKind {
    /// A map marker's visible, discovered, and travel flags. Keyed by the marker.
    public static let mapMarker = Self(rawValue: "mapMarker", order: 27, affectsCellBuild: false)
    /// The local map's explored squares. Keyed by the player.
    public static let localMapFog = Self(
        rawValue: "localMapFog",
        order: 28,
        affectsCellBuild: false
    )
}
