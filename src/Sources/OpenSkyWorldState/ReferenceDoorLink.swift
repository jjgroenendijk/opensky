// The door a random door linked itself to. Both doors carry it, so both lead to
// each other from then on. See docs/engine/random-doors.md.

import Foundation
public import OpenSkyFormatsESM

nonisolated public struct ReferenceDoorLink: WorldStateComponent, Hashable, Sendable {
    public let door: ReferenceKey

    public static var componentKind: WorldStateComponentKind {
        .doorLink
    }

    public init(door: ReferenceKey) {
        self.door = door
    }
}

nonisolated extension WorldStateComponentKind {
    /// A link changes no geometry; the door build reads it when the door is used.
    public static let doorLink = Self(rawValue: "doorLink", order: 48, affectsCellBuild: false)
}
