// Persistent harvested state of one FLOR or TREE reference, with the game day of
// the harvest so `HarvestRegrowth` can tell when it grows back.
// See docs/engine/interaction.md.

import OpenSkyWorldState

/// Set on a flora or tree reference once the player harvested it.
nonisolated public struct ReferenceHarvestState: WorldStateComponent, Hashable, Sendable {
    public var isHarvested: Bool
    /// Game days passed at the harvest. Nil when unknown, as in a save written
    /// before regrowth existed.
    public var harvestedOnDay: Float?

    public static let harvested = ReferenceHarvestState(isHarvested: true)

    public static var componentKind: WorldStateComponentKind {
        .harvest
    }

    public init(isHarvested: Bool, harvestedOnDay: Float? = nil) {
        self.isHarvested = isHarvested
        self.harvestedOnDay = harvestedOnDay
    }
}

nonisolated extension WorldStateComponentKind {
    /// Whether a flora or tree reference was harvested. Its own slot, so a reset
    /// can clear it without touching activation bookkeeping.
    public static let harvest = Self(rawValue: "harvest", order: 20)
}
