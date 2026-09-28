// Value types the M10.2 half of the World > Runtime State panel reads (issue
// #166): one game-clock sample, one global-variable sample, and one condition
// evaluation report.
//
// They live beside `RuntimeStateControlProviding` and carry no AppKit, so this
// file compiles into the app and the CLI target alike. Each type is a single
// sample rather than a bag of protocol properties for the same reason
// `RuntimeStateSnapshot` is: the readout must be a pure function of one engine
// observation instead of several taken microseconds apart.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// Number spelling shared by every M10.2 runtime-state readout, so a timescale,
/// a global value and a condition's right-hand side all read the same way.
nonisolated public enum RuntimeStateNumberText: Sendable {
    /// A whole number in its integer spelling, anything else through `%g`.
    /// The Creation Kit spells an integer-valued global and an integer CTDA
    /// comparison without a fraction, and "1.0" beside "1" in the same readout
    /// reads as two different values.
    ///
    /// A value outside the range `Int` can hold — a typo, not a game value —
    /// falls through to `%g` rather than trapping on the conversion.
    public static func text(_ value: Float) -> String {
        guard value.isFinite, abs(value) < 1e9, value == value.rounded() else {
            return String(format: "%g", value)
        }
        return String(Int(value))
    }
}

/// One sample of game time: the calendar the clock projects, the timescale the
/// advancement runs at, and whether the world simulation is paused.
///
/// The timescale is deliberately part of this sample even though it is not a
/// `GameClock` property — it is the `TimeScale` GLOB — because a reader asking
/// "what time is it and how fast is it moving?" must not see the two answers
/// from different moments.
nonisolated public struct RuntimeStateClockSnapshot: Equatable, Sendable {
    /// Fractional hour of day in [0, 24).
    public let hourOfDay: Float
    /// One-based day of the month.
    public let day: Int
    /// One-based month, 1 = Morning Star.
    public let month: Int
    public let monthName: String
    /// Fourth-era year, so 201 reads as 4E 201.
    public let year: Int
    /// Fractional days since the vanilla start date at midnight.
    public let daysPassed: Float
    /// Game seconds per wall-clock second, from the `TimeScale` global.
    public let timescale: Float
    /// Whether the world simulation is paused, which freezes the clock.
    public let isPaused: Bool

    public init(clock: GameClock, timescale: Float, isPaused: Bool) {
        hourOfDay = clock.hourOfDay
        day = clock.day
        month = clock.month
        monthName = clock.monthName
        year = clock.year
        daysPassed = clock.daysPassed
        self.timescale = timescale
        self.isPaused = isPaused
    }

    /// The vanilla start moment at the default timescale, running. Used as the
    /// panel's "no provider yet" reading, and as the fake provider's default so
    /// a fresh session reads as not overridden.
    public static let empty = RuntimeStateClockSnapshot(
        clock: GameClock(), timescale: GameClock.defaultTimescale, isPaused: false
    )

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

    public var pauseText: String {
        isPaused ? "paused" : "running"
    }
}

/// One global variable as the panel shows it: what the plugin authored, what
/// the session currently resolves, and whether those differ because a runtime
/// override was written.
///
/// `isOverridden` is not `defaultValue != currentValue`. Writing a global the
/// value it already had still records an override, and the five clock-projected
/// time globals resolve away from their plugin default without one, so the two
/// questions have genuinely different answers and both are shown.
nonisolated public struct RuntimeStateGlobalSnapshot: Equatable, Sendable {
    public let editorID: String
    /// Eight-digit hexadecimal FormID, as `FormID.description` spells it.
    public let formIDText: String
    /// Declared GLOB value type: "short", "long" or "float".
    public let typeName: String
    public let defaultValue: Float
    public let currentValue: Float
    public let isOverridden: Bool
    /// Record header flag 0x40. A constant global is still writable at runtime
    /// here; the flag is shown so a surprising result is explicable.
    public let isConstant: Bool

    public init(
        editorID: String,
        formIDText: String,
        typeName: String,
        defaultValue: Float,
        currentValue: Float,
        isOverridden: Bool,
        isConstant: Bool
    ) {
        self.editorID = editorID
        self.formIDText = formIDText
        self.typeName = typeName
        self.defaultValue = defaultValue
        self.currentValue = currentValue
        self.isOverridden = isOverridden
        self.isConstant = isConstant
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

    public static let empty = RuntimeStateConditionReport(
        source: "", isSatisfied: false, lines: [], tallyLines: [],
        message: "No condition list evaluated yet."
    )

    /// A stated non-answer, so a missing record reads as a reason rather than
    /// as an empty list that looks like a satisfied condition.
    public static func unavailable(source: String, message: String) -> RuntimeStateConditionReport {
        RuntimeStateConditionReport(
            source: source, isSatisfied: false, lines: [], tallyLines: [], message: message
        )
    }
}
