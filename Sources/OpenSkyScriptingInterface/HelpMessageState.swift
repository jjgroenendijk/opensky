// The help messages the player has seen, per input event. Kept on the player's
// delta so the save carries it in the `HELP` chunk. See docs/engine/messages.md.

import Foundation
import OpenSkyWorldState

/// What OpenSky keeps per help event.
nonisolated public struct HelpMessageRecord: Equatable, Sendable {
    public var timesShown: Int
    /// The player did the event, so the message is finished.
    public var isDone: Bool

    public init(timesShown: Int = 0, isDone: Bool = false) {
        self.timesShown = timesShown
        self.isDone = isDone
    }
}

nonisolated public struct HelpMessageState: WorldStateComponent, Sendable {
    /// Keyed by the lowercased event name.
    public var records: [String: HelpMessageRecord]

    public static var componentKind: WorldStateComponentKind {
        .helpMessages
    }

    public init(records: [String: HelpMessageRecord]) {
        self.records = records
    }
}

nonisolated extension WorldStateComponentKind {
    /// Help-message counts. Keyed by the player.
    public static let helpMessages = Self(rawValue: "helpMessages", order: 25)
}
