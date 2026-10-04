// HUD notifications in the order they were posted: each holds for a fixed time,
// at most `maximumVisible` show at once, and a repeat in the same frame is
// dropped. The timing is OpenSky's choice: docs/engine/messages.md#notifications.

import Foundation

nonisolated public struct NotificationQueue: Equatable, Sendable {
    nonisolated public struct Entry: Equatable, Sendable {
        public let text: String
        public let hold: Double
        public let frame: UInt64
        /// Nil while the entry waits for a free slot.
        public fileprivate(set) var shownAt: Double?
    }

    public static let defaultHold: Double = 3
    public static let maximumVisible = 3

    public private(set) var waiting: [Entry] = []
    public private(set) var visible: [Entry] = []
    public private(set) var postedCount = 0
    public private(set) var droppedCount = 0

    public init() {}

    /// Queues `text`. False for empty text and for a repeat of a line posted in
    /// the same frame, which two scripts reacting to one event would do.
    @discardableResult
    public mutating func post(_ text: String, hold: Double? = nil, frame: UInt64) -> Bool {
        guard !text.isEmpty else { return false }
        let repeated = (waiting + visible).contains { $0.frame == frame && $0.text == text }
        guard !repeated else {
            droppedCount += 1
            return false
        }
        waiting.append(Entry(text: text, hold: max(0.5, hold ?? Self.defaultHold), frame: frame))
        postedCount += 1
        return true
    }

    /// Retires entries whose hold ended and shows waiting ones in free slots.
    /// Returns the entries that became visible at `time`, oldest first.
    public mutating func advance(to time: Double) -> [Entry] {
        visible.removeAll { entry in entry.shownAt.map { time - $0 >= entry.hold } ?? true }
        var shown: [Entry] = []
        while visible.count < Self.maximumVisible, !waiting.isEmpty {
            var entry = waiting.removeFirst()
            entry.shownAt = time
            visible.append(entry)
            shown.append(entry)
        }
        return shown
    }
}
