// What the perk runtime did and declined to do, as counters. An unimplemented
// entry point returns the value it was handed, and these counters show it.
// See docs/engine/perks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyProgressionInterface

nonisolated public struct PerkRuntimeTally: Equatable, Sendable {
    /// Add or seed calls naming a PERK no loaded plugin carries.
    public private(set) var unresolvedPerks = 0
    /// Entry-point evaluations that ran at all.
    public private(set) var evaluations = 0
    /// Effects whose function produces something other than a number, or whose
    /// payload did not match its function. Keyed by the function's description
    /// so a readout ranks them without a second table.
    public private(set) var unsupportedFunctions: [String: Int] = [:]
    /// Condition tabs skipped because no reference was bound for their subject, by
    /// subject. This is the one documented over-application: the effect then applies
    /// more widely than the record asks.
    public private(set) var unboundConditionSubjects: [PerkConditionSubject: Int] = [:]
    /// Condition tabs that were evaluated and came out false, which is a perk
    /// correctly not applying rather than a gap.
    public private(set) var conditionsFailed = 0
    /// Effects skipped because an actor-value function had no value to read.
    public private(set) var unavailableActorValues = 0

    public mutating func noteUnresolvedPerk() {
        unresolvedPerks += 1
    }

    public mutating func noteEvaluation() {
        evaluations += 1
    }

    public mutating func noteConditionFailed() {
        conditionsFailed += 1
    }

    public mutating func noteUnboundSubject(_ subject: PerkConditionSubject) {
        unboundConditionSubjects[subject, default: 0] += 1
    }

    public mutating func note(_ skip: PerkEntryPointSkip) {
        switch skip {
        case let .unsupportedFunction(function), let .missingData(function),
             let .nonFiniteResult(function):
            unsupportedFunctions[function.description, default: 0] += 1
        case .unavailableActorValue:
            unavailableActorValues += 1
        }
    }
}
