// Persistent harvested state of one FLOR or TREE reference. A later cell-reset
// system clears this component to regrow the plant.
// See docs/engine/interaction.md.

import OpenSkyWorldState

/// Set on a flora or tree reference once the player harvested it.
nonisolated public struct ReferenceHarvestState: WorldStateComponent, Hashable, Sendable {
    public var isHarvested: Bool

    public static let harvested = ReferenceHarvestState(isHarvested: true)

    public static var componentKind: WorldStateComponentKind {
        .harvest
    }

    public init(isHarvested: Bool) {
        self.isHarvested = isHarvested
    }
}

nonisolated extension WorldStateComponentKind {
    /// Whether a flora or tree reference was harvested. Its own slot, so a reset
    /// can clear it without touching activation bookkeeping.
    public static let harvest = Self(rawValue: "harvest", order: 20)
}
