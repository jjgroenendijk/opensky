// A plugin reference the running game moved into another cell, as `MoveTo` does.
// The place is the `transform` component; this one names the cell that draws it,
// because a persistent exterior reference is drawn by the cell its plugin
// position falls in. See docs/engine/reference-identity.md.

import Foundation
public import OpenSkyGameData

nonisolated public struct ReferenceRelocation: WorldStateComponent, Hashable, Sendable {
    public let location: CellSceneLocation
    /// The worldspace editor ID of an exterior cell, because a city world and Tamriel share
    /// grid coordinates. Nil for an interior, or when the mover did not know it.
    public let worldspace: String?

    public static var componentKind: WorldStateComponentKind {
        .relocation
    }

    public init(location: CellSceneLocation, worldspace: String? = nil) {
        self.location = location
        self.worldspace = worldspace
    }

    /// True when the cell `location` of `worldspace` draws the reference. A move with no
    /// worldspace lands in that cell of any worldspace.
    public func lands(in location: CellSceneLocation, worldspace: String?) -> Bool {
        guard location == self.location, let own = self.worldspace else {
            return location == self.location
        }
        return worldspace.map { $0.caseInsensitiveCompare(own) == .orderedSame } ?? false
    }
}

nonisolated extension WorldStateComponentKind {
    public static let relocation = Self(rawValue: "relocation", order: 31)
}

nonisolated extension ReferenceStateDelta {
    /// True when this delta moved its reference out to a cell other than `location` of
    /// `worldspace`.
    public func relocatesAway(from location: CellSceneLocation, worldspace: String?) -> Bool {
        guard let moved = component(ReferenceRelocation.self) else { return false }
        return !moved.lands(in: location, worldspace: worldspace)
    }
}
