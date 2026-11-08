// Value types the Runtime State readout reads: a game-clock sample, a global sample, and a
// condition report. Each is one sample, so the readout comes from one observation.
// See docs/engine/runtime-state.md.

import Foundation
import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Number spelling shared by runtime-state readouts, so every value reads the same way.
nonisolated public enum RuntimeStateNumberText: Sendable {
    /// A whole number without a fraction, like the Creation Kit; anything else, or a value
    /// outside `Int`, through `%g`.
    public static func text(_ value: Float) -> String {
        guard value.isFinite, abs(value) < 1e9, value == value.rounded() else {
            return unsafe String(format: "%g", value)
        }
        return String(Int(value))
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
