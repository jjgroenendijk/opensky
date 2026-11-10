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
nonisolated struct RuntimeStateConditionLine: Equatable, Sendable {
    /// One-based position in the authored list.
    let index: Int
    /// `<function> <operator> <right-hand side>`, plus an `(or)` marker when
    /// the condition is OR-joined to the one after it.
    let text: String
    let isTrue: Bool
    /// Why this condition answered as it did: "true", "false", or the
    /// `ConditionFailure` spelled out.
    let reason: String
}

/// The result of evaluating one condition list against the live context.
nonisolated struct RuntimeStateConditionReport: Equatable, Sendable {
    /// Name of the record the list came from.
    let source: String
    /// The list's overall verdict under the documented OR grouping.
    let isSatisfied: Bool
    let lines: [RuntimeStateConditionLine]
    /// Preformatted `ConditionTally` counters, one per line.
    let tallyLines: [String]
    /// Set when no evaluation happened, stating why. Nil on a real result.
    let message: String?

    init(
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
    static func unavailable(source: String, message: String) -> RuntimeStateConditionReport {
        RuntimeStateConditionReport(
            source: source, isSatisfied: false, lines: [], tallyLines: [], message: message
        )
    }
}
