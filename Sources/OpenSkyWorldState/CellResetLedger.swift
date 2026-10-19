// When the player last left each cell, so a cell can reset on the next visit. The rule
// is the CK wiki "Cell Reset" page; see docs/engine/cell-reset.md.

import OpenSkyGameData

/// Kept on the player: the game hour of the last departure from each cell.
nonisolated public struct CellResetLedger: WorldStateComponent, Hashable, Sendable {
    /// `GameClock.totalGameSeconds` / 3600 at the moment the cell stopped being resident.
    public var departures: [CellSceneLocation: Double]

    public static var componentKind: WorldStateComponentKind {
        .cellReset
    }

    public init(departures: [CellSceneLocation: Double] = [:]) {
        self.departures = departures
    }
}

nonisolated extension WorldStateComponentKind {
    public static let cellReset = Self(rawValue: "cellReset", order: 36, affectsCellBuild: false)
}

/// `iHoursToRespawnCell` and `iHoursToRespawnCellCleared`, in game hours.
nonisolated public struct CellResetSettings: Equatable, Sendable {
    /// The CK wiki defaults, which `Skyrim.esm` also sets.
    public var hours = 240
    public var clearedHours = 720

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("iHoursToRespawnCell", into: &settings, \.hours)
        store.read("iHoursToRespawnCellCleared", into: &settings, \.clearedHours)
        return settings
    }

    /// A cell resets when the player comes back after enough game hours away. A
    /// cleared location waits the longer interval.
    public func isDue(departedAt departure: Double, now: Double, cleared: Bool) -> Bool {
        guard departure.isFinite, now.isFinite else { return false }
        return now - departure >= Double(cleared ? clearedHours : hours)
    }
}
