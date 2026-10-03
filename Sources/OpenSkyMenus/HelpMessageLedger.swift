// `Message.ShowAsHelpMessage` bookkeeping. Per the Creation Kit wiki the event
// "both identifies and ends the help message": once it happens, the message does
// not show again until `ResetHelpMessage`. See docs/engine/messages.md#help-messages.

import Foundation
import OpenSkyScriptingInterface

nonisolated public struct HelpMessageLedger: Equatable, Sendable {
    nonisolated public struct Active: Equatable, Sendable {
        public let event: String
        public let text: String
        /// Seconds on screen; zero or less means until the event happens.
        public let duration: Double
        public let interval: Double
        /// Zero or less means no limit.
        public let maxTimes: Int
        public fileprivate(set) var shownAt: Double?
        public fileprivate(set) var hiddenAt: Double?
    }

    public private(set) var records: [String: HelpMessageRecord]
    public private(set) var active: Active?

    public init(records: [String: HelpMessageRecord] = [:]) {
        self.records = records
    }

    /// The text on screen at the last `advance`, or nil.
    public var visibleText: String? {
        guard let active, active.shownAt != nil, active.hiddenAt == nil else { return nil }
        return active.text
    }

    /// Starts a help message, replacing any other. False when the event is
    /// done or the message already reached its limit.
    @discardableResult
    public mutating func show(
        event: String, text: String, duration: Double, interval: Double, maxTimes: Int
    ) -> Bool {
        let key = Self.key(event)
        let record = records[key] ?? HelpMessageRecord()
        guard !record.isDone, !Self.reachedLimit(record, maxTimes) else { return false }
        active = Active(
            event: key, text: text, duration: duration, interval: max(0, interval),
            maxTimes: maxTimes
        )
        return true
    }

    /// Shows, hides, and re-shows the active message. Returns true when the
    /// visible text changed.
    public mutating func advance(to time: Double) -> Bool {
        guard var current = active else { return false }
        let before = visibleText
        var record = records[current.event] ?? HelpMessageRecord()
        if let shown = current.shownAt, current.hiddenAt == nil {
            if current.duration > 0, time - shown >= current.duration {
                current.hiddenAt = time
            }
        } else if current.shownAt == nil || time - (current.hiddenAt ?? time) >= current.interval {
            if Self.reachedLimit(record, current.maxTimes) {
                active = nil
                return before != nil
            }
            current.shownAt = time
            current.hiddenAt = nil
            record.timesShown += 1
            records[current.event] = record
        }
        active = current
        return before != visibleText
    }

    /// The player did `event`: its message is done and hides.
    public mutating func noteEvent(_ event: String) {
        let key = Self.key(event)
        guard active?.event == key || records[key] != nil else { return }
        records[key, default: HelpMessageRecord()].isDone = true
        if active?.event == key {
            active = nil
        }
    }

    /// `ResetHelpMessage`: the event may show a message again.
    public mutating func reset(event: String) {
        let key = Self.key(event)
        records[key] = nil
        if active?.event == key {
            active = nil
        }
    }

    public mutating func resetAll() {
        records.removeAll()
        active = nil
    }

    /// Event names match the way input events do, without case.
    static func key(_ event: String) -> String {
        event.lowercased()
    }

    private static func reachedLimit(_ record: HelpMessageRecord, _ maxTimes: Int) -> Bool {
        maxTimes > 0 && record.timesShown >= maxTimes
    }
}
