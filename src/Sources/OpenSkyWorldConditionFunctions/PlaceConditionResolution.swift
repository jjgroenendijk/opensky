// The place facts the world condition functions read: deaths, the player's
// regions, and the visible map markers (docs/engine/condition-functions-world.md#locations).

import Foundation
public import OpenSkyConditions
public import OpenSkyFormatsESM

/// Who died, where the player stands, and which map markers show.
nonisolated public struct PlaceConditionResolution: ConditionResolution, Sendable {
    public static let empty = PlaceConditionResolution()

    /// Nil without a world state to read deaths from.
    public let deadReferences: Set<ReferenceKey>?
    /// Dead placed actors per NPC_ base, raw FormIDs as the plugin spells them.
    public let deadCounts: [FormID: Int]
    /// The REGN records over the player's exterior cell, raw FormIDs.
    public let playerRegions: Set<FormID>?
    public let visibleMarkers: Set<ReferenceKey>?

    public init(
        deadReferences: Set<ReferenceKey>? = nil,
        deadCounts: [FormID: Int] = [:],
        playerRegions: Set<FormID>? = nil,
        visibleMarkers: Set<ReferenceKey>? = nil
    ) {
        self.deadReferences = deadReferences
        self.deadCounts = deadCounts
        self.playerRegions = playerRegions
        self.visibleMarkers = visibleMarkers
    }
}
