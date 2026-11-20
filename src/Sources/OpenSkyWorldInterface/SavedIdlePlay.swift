// The idle an actor plays when the game saves, and the idle's target. A load plays it
// again on the actor (docs/engine/idle-runtime.md#what-a-save-keeps).

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyWorldState

nonisolated public struct SavedIdlePlay: WorldStateComponent, Sendable {
    /// The `IDLE` record, by plugin name, so a reordered load order still finds it.
    public let idle: ResolvedFormID
    /// The reference the idle was fired at, such as the other half of a pair.
    public let target: ReferenceKey?

    public static var componentKind: WorldStateComponentKind {
        .savedIdlePlay
    }

    public init(idle: ResolvedFormID, target: ReferenceKey? = nil) {
        self.idle = idle
        self.target = target
    }
}

nonisolated extension WorldStateComponentKind {
    /// The idle an actor played when the game saved. Keyed by the actor.
    public static let savedIdlePlay = Self(
        rawValue: "savedIdlePlay", order: 49, affectsCellBuild: false
    )
}
