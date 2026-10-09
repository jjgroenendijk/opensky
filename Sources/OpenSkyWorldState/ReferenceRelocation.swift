// A plugin reference the running game moved into another cell, as `MoveTo` does.
// The place is the `transform` component; this one names the cell that draws it,
// because a persistent exterior reference is drawn by the cell its plugin
// position falls in. See docs/engine/reference-identity.md.

import Foundation
import OpenSkyGameData

nonisolated public struct ReferenceRelocation: WorldStateComponent, Hashable, Sendable {
    public let location: CellSceneLocation

    public static var componentKind: WorldStateComponentKind {
        .relocation
    }

    public init(location: CellSceneLocation) {
        self.location = location
    }
}

nonisolated extension WorldStateComponentKind {
    public static let relocation = Self(rawValue: "relocation", order: 31)
}

nonisolated extension ReferenceStateDelta {
    /// True when this delta moved its reference out to a cell other than `location`.
    public func relocatesAway(from location: CellSceneLocation) -> Bool {
        guard let moved = component(ReferenceRelocation.self) else { return false }
        return moved.location != location
    }
}
