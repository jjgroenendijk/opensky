// What the perk runtime did and declined to do (issue #497, roadmap item 20.4).
//
// Shaped like `ActiveEffectTally` and `ConditionTally`: every gap is a counter
// rather than a log line, so a sweep asserts a number and a panel prints one.
// The rule the whole subsystem follows is that an entry point nothing
// implements evaluates to the value it was handed — identity, never zero — and
// these counters are what make that visible instead of silent.
//
// Documented in docs/engine/perks.md.

import Foundation

nonisolated struct PerkRuntimeTally: Equatable, Sendable {
    /// Add or seed calls naming a PERK no loaded plugin carries.
    private(set) var unresolvedPerks = 0
    /// Entry-point evaluations that ran at all.
    private(set) var evaluations = 0
    /// Effects whose function produces something other than a number, or whose
    /// payload did not match its function. Keyed by the function's description
    /// so a readout ranks them without a second table.
    private(set) var unsupportedFunctions: [String: Int] = [:]
    /// Condition tabs skipped because the caller bound no reference for the
    /// subject they run against, keyed by that subject.
    ///
    /// This is the subsystem's one documented over-application: a weapon-type
    /// tab that nothing can bind is *not* evaluated, so the effect applies more
    /// widely than the record asks. Counting it per subject is what says how
    /// much, and to what.
    private(set) var unboundConditionSubjects: [PerkConditionSubject: Int] = [:]
    /// Condition tabs that were evaluated and came out false, which is a perk
    /// correctly not applying rather than a gap.
    private(set) var conditionsFailed = 0
    /// Effects skipped because an actor-value function had no value to read.
    private(set) var unavailableActorValues = 0

    var isClean: Bool {
        unresolvedPerks == 0
            && unsupportedFunctions.isEmpty
            && unboundConditionSubjects.isEmpty
            && unavailableActorValues == 0
    }

    /// Unsupported functions ranked by count, ties broken by name so the order
    /// is stable.
    var rankedUnsupportedFunctions: [(name: String, count: Int)] {
        unsupportedFunctions
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    mutating func noteUnresolvedPerk() {
        unresolvedPerks += 1
    }

    mutating func noteEvaluation() {
        evaluations += 1
    }

    mutating func noteConditionFailed() {
        conditionsFailed += 1
    }

    mutating func noteUnboundSubject(_ subject: PerkConditionSubject) {
        unboundConditionSubjects[subject, default: 0] += 1
    }

    mutating func note(_ skip: PerkEntryPointSkip) {
        switch skip {
        case let .unsupportedFunction(function), let .missingData(function),
             let .nonFiniteResult(function):
            unsupportedFunctions[function.description, default: 0] += 1
        case .unavailableActorValue:
            unavailableActorValues += 1
        }
    }
}
