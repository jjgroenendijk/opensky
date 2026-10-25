// Value types the Runtime State readout reads: a game-clock sample, a global sample, and a
// condition report. Each is one sample, so the readout comes from one observation.
// See docs/engine/runtime-state.md.

import Foundation
import OpenSkyGameData
import OpenSkyWorldState

/// Number spelling shared by runtime-state readouts, so every value reads the same way.
nonisolated public enum RuntimeStateNumberText: Sendable {
    /// A whole number without a fraction, like the Creation Kit; anything else, or a value
    /// outside `Int`, through `%g`.
    public static func text(_ value: Float) -> String {
        guard value.isFinite, abs(value) < 1e9, value == value.rounded() else {
            return String(format: "%g", value)
        }
        return String(Int(value))
    }
}

/// One game-time sample: calendar, timescale and pause. The timescale is the `TimeScale`
/// GLOB, not a clock property, but it belongs in the same sample.
nonisolated public struct RuntimeStateClockSnapshot: Equatable, Sendable {
    /// Fractional hour of day in [0, 24).
    public let hourOfDay: Float
    /// One-based day of the month.
    public let day: Int
    public let monthName: String
    /// Fourth-era year, so 201 reads as 4E 201.
    public let year: Int
    /// Fractional days since the vanilla start date at midnight.
    public let daysPassed: Float
    /// Game seconds per wall-clock second, from the `TimeScale` global.
    public let timescale: Float

    public init(
        clock: GameClock, timescale: Float
    ) {
        hourOfDay = clock.hourOfDay
        day = clock.day
        monthName = clock.monthName
        year = clock.year
        daysPassed = clock.daysPassed
        self.timescale = timescale
    }

    /// Twenty-four-hour wall spelling of `hourOfDay`, minutes truncated rather
    /// than rounded so a readout never shows the next hour before it arrives.
    public var timeText: String {
        let clamped = hourOfDay.isFinite ? min(max(0, hourOfDay), 24) : 0
        let hour = Int(clamped.rounded(.down))
        let minute = Int(((clamped - Float(hour)) * 60).rounded(.down))
        return String(format: "%02d:%02d", hour, min(minute, 59))
    }

    /// Calendar spelling, in the in-game order: day, month name, era and year.
    public var dateText: String {
        "\(day) \(monthName), 4E \(year)"
    }
}

/// One global: authored value, current value, and whether an override was written. Not
/// `defaultValue != currentValue`: writing the same value records an override, and the
/// clock-projected time globals differ without one.
nonisolated public struct RuntimeStateGlobalSnapshot: Equatable, Sendable {
    public let editorID: String
    public let defaultValue: Float
    public let currentValue: Float
    public let isOverridden: Bool

    public init(
        editorID: String,
        defaultValue: Float,
        currentValue: Float,
        isOverridden: Bool
    ) {
        self.editorID = editorID
        self.defaultValue = defaultValue
        self.currentValue = currentValue
        self.isOverridden = isOverridden
    }
}

/// One condition's own verdict inside an evaluated list.
nonisolated public struct RuntimeStateConditionLine: Equatable, Sendable {
    /// One-based position in the authored list.
    public let index: Int
    /// `<function> <operator> <right-hand side>`, plus an `(or)` marker when
    /// the condition is OR-joined to the one after it.
    public let text: String
    public let isTrue: Bool
    /// Why this condition answered as it did: "true", "false", or the
    /// `ConditionFailure` spelled out.
    public let reason: String
}

/// The result of evaluating one condition list against the live context.
nonisolated public struct RuntimeStateConditionReport: Equatable, Sendable {
    /// Name of the record the list came from.
    public let source: String
    /// The list's overall verdict under the documented OR grouping.
    public let isSatisfied: Bool
    public let lines: [RuntimeStateConditionLine]
    /// Preformatted `ConditionTally` counters, one per line.
    public let tallyLines: [String]
    /// Set when no evaluation happened, stating why. Nil on a real result.
    public let message: String?

    public init(
        source: String,
        isSatisfied: Bool,
        lines: [RuntimeStateConditionLine],
        tallyLines: [String],
        message: String? = nil
    ) {
        self.source = source
        self.isSatisfied = isSatisfied
        self.lines = lines
        self.tallyLines = tallyLines
        self.message = message
    }

    /// A stated non-answer, so a missing record reads as a reason rather than
    /// as an empty list that looks like a satisfied condition.
    public static func unavailable(source: String, message: String) -> RuntimeStateConditionReport {
        RuntimeStateConditionReport(
            source: source, isSatisfied: false, lines: [], tallyLines: [], message: message
        )
    }
}
