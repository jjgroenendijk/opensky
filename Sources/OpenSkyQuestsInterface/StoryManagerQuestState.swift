// What the story manager remembers about one quest it started, keyed by the
// QUST's `ReferenceKey`: when it last started it and how often. Hours until
// reset and "do all before repeating" read it. See docs/engine/story-manager.md.

import Foundation
import OpenSkyWorldState

nonisolated public struct StoryManagerQuestState: WorldStateComponent, Sendable {
    /// `GameClock.totalGameSeconds` at the last start.
    public var lastStartSeconds: Double
    public var startCount: UInt32

    public static var componentKind: WorldStateComponentKind {
        .storyManager
    }

    public init(lastStartSeconds: Double, startCount: UInt32) {
        self.lastStartSeconds = lastStartSeconds
        self.startCount = startCount
    }

    /// Whether `hours` of game time passed since the last start. Zero hours never blocks.
    public func hasReset(after hours: Float, now seconds: Double) -> Bool {
        hours <= 0 || seconds - lastStartSeconds >= Double(hours) * GameClock.secondsPerHour
    }

    public func started(at seconds: Double) -> Self {
        Self(lastStartSeconds: seconds, startCount: startCount == .max ? .max : startCount + 1)
    }
}

nonisolated extension WorldStateComponentKind {
    /// A story-manager start record. Keyed by the QUST base record, which is in no cell.
    public static let storyManager = Self(rawValue: "storyManager", order: 23)
}
