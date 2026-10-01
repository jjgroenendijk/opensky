// The CTDA condition evaluator. It never throws: an unanswerable condition is false
// with a `ConditionFailure`, counted in `ConditionTally`. `==` is exact; no source
// gives a tolerance. An OR flag binds condition N to N+1, so `A AND B(or) C AND D` is
// `A AND (B OR C) AND D`; an empty list is true. Sources: UESP "Skyrim Mod:Mod File
// Format/CTDA Field", Creation Kit wiki "Conditions", xEdit wbDefinitionsTES5.pas
// (`wbCTDA`).

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated public enum ConditionDataDomain: String, Equatable, Sendable {
    case keyword
    case formList
    case location
}

/// Which half of the magic seam could not answer. Four cases, because each names a
/// different gap: actor state, a parameter's record, an unreadied source, an empty hand.
nonisolated public enum ConditionMagicDomain: String, Equatable, Sendable {
    /// The run-on named a reference the magic seam carries no state for.
    case actor
    /// A FormID parameter, or a readied spell, that this load order does not
    /// resolve to a record.
    case record
    /// A casting source that is not one of the two hands OpenSky readies
    /// spells into — the voice slot and the instant source.
    case castingSource
    /// The named casting source holds no spell, so the SPIT field the function
    /// reads does not exist.
    case equippedSpell
}

/// Why a condition could not be evaluated. Every case is a reason-tagged false
/// and a `ConditionTally` bucket.
///
/// The `Error` conformance exists only so these can ride in a `Result`; nothing
/// in the evaluator ever throws one, and no caller should catch one. Missing
/// coverage is a value here, not a control-flow event.
nonisolated public enum ConditionFailure: Equatable, Error, Sendable {
    /// Raw on-disk function index with no registry entry (Creation Kit spells
    /// this number 4096 higher).
    case unknownFunction(UInt16)
    /// A `use global` comparison value, or a GLOB parameter, that resolves to
    /// no global. Deliberately not treated as zero.
    case unresolvedGlobal(FormID)
    /// A QUST parameter that resolves to no quest. Not a stopped quest at stage zero:
    /// "does not exist" and "has not started" are different answers.
    case unresolvedQuest(FormID)
    /// A run-on type OpenSky does not resolve live yet.
    case unsupportedRunOn(Condition.RunOnType)
    /// A supported run-on that named a reference the context cannot produce.
    case unresolvedReference(Condition.RunOnType)
    /// Operator bits 6 or 7, which are undefined on disk.
    case unknownOperator(UInt8)
    /// The function needs a parameter it cannot read: a CIS1/CIS2 alias name that
    /// matches no filled alias, or an unknown actor value. Carries the raw index.
    case unresolvedParameter(UInt16)
    /// The function needs game time and the context carries no clock.
    case unavailableClock
    /// The function needs actor state the context lacks: no `ActorStateResolution`
    /// entry, or no observed draw state. Not a neutral, sheathed actor.
    case unavailableActorState
    /// The function needs perception the context lacks: no `DetectionResolution`
    /// entry for the pair, or no position. Not an undetected actor in clear sight.
    case unavailableDetection
    /// The function needs a dialogue fact the context lacks: no `DialogueResolution`
    /// voice type for the run-on. Not a voice mismatch.
    case unavailableDialogue
    /// A record-data function had no store, subject fact, or resolvable FormID for the
    /// named domain. This is not a negative query result.
    case unavailableData(ConditionDataDomain)
    /// `HasPerk` without PERK data, or with an unresolved parameter. Not an actor
    /// who lacks the perk.
    case unavailablePerks
    /// `GetCrimeGold` without FACT data, with an unresolved parameter, or with a null
    /// parameter outside any hold. Not an actor who owes nothing.
    case unavailableCrime
    /// A faction or relationship function without FACT data, with an unresolved
    /// parameter, or about an actor with no social profile. Not a factionless actor.
    case unavailableFactions
    /// A magic function had no state, record or slot for the named domain. Not an
    /// actor with no spells or effects.
    case unavailableMagic(ConditionMagicDomain)
}

/// The answer to one condition or one condition list.
///
/// `isTrue` is always usable: a condition that could not be evaluated is false
/// and names why in `failures`, so a caller that only wants a Bool never has to
/// handle an error path.
nonisolated public struct ConditionOutcome: Equatable, Sendable {
    public let isTrue: Bool
    /// Reasons for every condition that could not produce a real answer, in
    /// evaluation order. Empty when the whole list evaluated cleanly.
    public let failures: [ConditionFailure]

    public static let `true` = ConditionOutcome(isTrue: true, failures: [])
    public static let `false` = ConditionOutcome(isTrue: false, failures: [])

    public init(isTrue: Bool, failures: [ConditionFailure] = []) {
        self.isTrue = isTrue
        self.failures = failures
    }

    /// True when the outcome came from real answers rather than from a
    /// fallback.
    public var isConclusive: Bool {
        failures.isEmpty
    }
}

/// Deterministic 0-99 source for `GetRandomPercent`, seeded per session or per test.
/// SplitMix64 (Steele, Lea and Flood, OOPSLA 2014): one mixing step, no warm-up, no table.
nonisolated public struct ConditionRandom: Equatable, Sendable {
    /// SplitMix64's golden-ratio increment, also this generator's default seed.
    public static let defaultSeed: UInt64 = 0x9E37_79B9_7F4A_7C15

    private var state: UInt64

    public init(seed: UInt64 = ConditionRandom.defaultSeed) {
        state = seed
    }

    /// Next raw 64-bit draw.
    public mutating func next() -> UInt64 {
        state &+= Self.defaultSeed
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Next integer in 0...99 **inclusive** — `GetRandomPercent` never returns
    /// 100 (Creation Kit wiki "GetRandomPercent"). The modulo bias over a
    /// 64-bit draw is below one part in 2^57 and is not corrected for.
    public mutating func percent() -> Int {
        Int(next() % 100)
    }
}

/// Evaluates CTDA conditions against a `ConditionContext`. Mutating, because the
/// tally and the random stream advance. It never short-circuits, so the tally covers
/// the whole list.
nonisolated public struct ConditionEvaluator: Sendable {
    public var context: ConditionContext
    public let registry: ConditionFunctionRegistry
    public private(set) var tally: ConditionTally

    public init(
        context: ConditionContext,
        registry: ConditionFunctionRegistry,
        tally: ConditionTally = ConditionTally()
    ) {
        self.context = context
        self.registry = registry
        self.tally = tally
    }

    // MARK: - Evaluation

    /// Evaluates one condition: `functionReturn <operator> comparisonValue`.
    public mutating func evaluate(_ condition: Condition) -> ConditionOutcome {
        tally.noteCondition()
        switch result(of: condition) {
        case let .success(isTrue):
            return ConditionOutcome(isTrue: isTrue)
        case let .failure(failure):
            tally.note(failure)
            return ConditionOutcome(isTrue: false, failures: [failure])
        }
    }

    /// Evaluates a whole condition run with OR grouping (see the file header).
    /// An empty run is true, which is what an unconditioned record means.
    public mutating func evaluate(_ conditions: [Condition]) -> ConditionOutcome {
        tally.noteList()
        guard !conditions.isEmpty else { return .true }

        var failures: [ConditionFailure] = []
        var result = true
        var block = false
        for condition in conditions {
            let outcome = evaluate(condition)
            failures.append(contentsOf: outcome.failures)
            block = block || outcome.isTrue
            if !condition.flags.contains(.or) {
                result = result && block
                block = false
            }
        }
        // A trailing OR flag has no following operator, so the last block ends
        // with the list rather than dangling.
        if conditions[conditions.count - 1].flags.contains(.or) {
            result = result && block
        }
        return ConditionOutcome(isTrue: result, failures: failures)
    }

    /// Convenience over a decoded `ConditionList`.
    public mutating func evaluate(_ list: ConditionList) -> ConditionOutcome {
        evaluate(list.conditions)
    }

    // MARK: - One condition

    private mutating func result(of condition: Condition) -> Result<Bool, ConditionFailure> {
        guard let function = registry[condition.functionIndex] else {
            return .failure(.unknownFunction(condition.functionIndex))
        }
        var call = ConditionCall(condition: condition, context: context)
        let value = function.body(&call)
        context = call.context
        switch value {
        case let .failure(failure):
            return .failure(failure)
        case let .success(left):
            return comparisonValue(of: condition).flatMap { right in
                guard let isTrue = Self.compare(left, condition.comparison, right) else {
                    return .failure(.unknownOperator(Self.operatorBits(condition.comparison)))
                }
                return .success(isTrue)
            }
        }
    }

    /// The right-hand side, through the documented globals seam. A `use global`
    /// comparison naming no global is unevaluatable, never a compare to zero.
    private func comparisonValue(of condition: Condition) -> Result<Float, ConditionFailure> {
        switch condition.comparisonValue {
        case let .value(literal):
            return .success(literal)
        case let .global(id):
            guard let value = context.globals.comparisonValue(condition.comparisonValue) else {
                return .failure(.unresolvedGlobal(id))
            }
            return .success(value)
        }
    }

    /// Exact float comparison — see the file header on why no epsilon. Nil for
    /// the two undefined operator encodings.
    public static func compare(
        _ left: Float,
        _ comparison: Condition.ComparisonOperator,
        _ right: Float
    ) -> Bool? {
        switch comparison {
        case .equal: left == right
        case .notEqual: left != right
        case .greaterThan: left > right
        case .greaterThanOrEqual: left >= right
        case .lessThan: left < right
        case .lessThanOrEqual: left <= right
        case .unknown: nil
        }
    }

    /// The raw top-3-bit encoding of an operator, for failure reporting.
    private static func operatorBits(_ comparison: Condition.ComparisonOperator) -> UInt8 {
        switch comparison {
        case .equal: 0
        case .notEqual: 1
        case .greaterThan: 2
        case .greaterThanOrEqual: 3
        case .lessThan: 4
        case .lessThanOrEqual: 5
        case let .unknown(raw): raw
        }
    }
}
