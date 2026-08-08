// Per-function coverage tally for the real-data CTDA sweep (issue #251),
// split out of `ConditionRealDataTests` to stay inside the file-length cap.
//
// This answers two questions the sweep exists to answer. First, "how much of
// the condition traffic in a real plugin can OpenSky actually evaluate today?",
// which is the ratio of conditions whose raw function index is in
// `ConditionFunctionRegistry.standard` to conditions overall, plus a ranked
// list of the misses so the next function to implement is the one that buys the
// most. Second, "what shape does a given function index have on disk?", which
// is how a disputed index is settled: a function that takes no parameters
// leaves both parameter words zero in every authored condition, and a function
// returning a percentage is compared against values spread over 0-100.
//
// Everything here is aggregate. No count identifies an individual record, so
// the report is a statistic about the user's install rather than an extract of
// it (AGENTS.md Legal & IP), and it is written only to gitignored `logs/`.

import Foundation
@testable import opensky

/// How one raw function index is actually used across every CTDA seen.
struct ConditionFunctionShape {
    /// Distinct comparison values kept before the set stops growing, so a
    /// pathological plugin cannot make the tally grow without bound.
    static let distinctComparisonLimit = 256

    /// How many conditions in the sweep used this index.
    private(set) var conditions = 0
    /// Conditions where the function's first parameter word is not zero. A
    /// function declaring no parameters should hold this at zero.
    private(set) var parameter1Nonzero = 0
    private(set) var parameter2Nonzero = 0
    /// Comparisons against a GLOB FormID rather than a literal.
    private(set) var globalComparisons = 0
    private(set) var literalComparisons = 0
    /// Literal comparisons falling inside 0-100 inclusive.
    private(set) var percentRangeComparisons = 0
    private(set) var minimumComparison: Float?
    private(set) var maximumComparison: Float?
    private(set) var distinctComparisonBits: Set<UInt32> = []
    private(set) var runOnHistogram: [String: Int] = [:]

    mutating func record(_ condition: Condition) {
        conditions += 1
        if condition.parameter1.rawValue != 0 {
            parameter1Nonzero += 1
        }
        if condition.parameter2.rawValue != 0 {
            parameter2Nonzero += 1
        }
        runOnHistogram[ConditionTally.runOnName(condition.runOn), default: 0] += 1
        switch condition.comparisonValue {
        case let .value(value): recordComparison(value)
        case .global: globalComparisons += 1
        }
    }

    private mutating func recordComparison(_ value: Float) {
        literalComparisons += 1
        guard value.isFinite else { return }
        if value >= 0, value <= 100 {
            percentRangeComparisons += 1
        }
        minimumComparison = Swift.min(minimumComparison ?? value, value)
        maximumComparison = Swift.max(maximumComparison ?? value, value)
        if distinctComparisonBits.count < Self.distinctComparisonLimit {
            distinctComparisonBits.insert(value.bitPattern)
        }
    }

    /// True when no authored condition on this index carried either parameter
    /// word, which is the on-disk fingerprint of a no-parameter function.
    var takesNoParameters: Bool {
        conditions > 0 && parameter1Nonzero == 0 && parameter2Nonzero == 0
    }

    /// One line of shape evidence, for the disputed-index probe.
    var signature: String {
        let bounds = minimumComparison.map { minimum in
            "\(minimum)...\(maximumComparison ?? minimum)"
        } ?? "none"
        let runOns = runOnHistogram.sorted { $0.value > $1.value }
            .prefix(4).map { "\($0.key):\($0.value)" }.joined(separator: " ")
        return """
        n=\(conditions) param1!=0:\(parameter1Nonzero) param2!=0:\(parameter2Nonzero) \
        literal:\(literalComparisons) global:\(globalComparisons) \
        range:\(bounds) in0...100:\(percentRangeComparisons) \
        distinct:\(distinctComparisonBits.count) runOn[\(runOns)]
        """
    }
}

/// Frequency of every raw condition-function index across a whole plugin, and
/// the registry coverage that follows from it.
struct ConditionCoverage {
    private(set) var shapes: [UInt16: ConditionFunctionShape] = [:]
    private(set) var total = 0

    mutating func record(_ condition: Condition) {
        total += 1
        shapes[condition.functionIndex, default: ConditionFunctionShape()]
            .record(condition)
    }

    // MARK: - Coverage

    var distinctIndices: Int {
        shapes.count
    }

    var indexBounds: (minimum: UInt16, maximum: UInt16) {
        (shapes.keys.min() ?? 0, shapes.keys.max() ?? 0)
    }

    func conditions(of index: UInt16) -> Int {
        shapes[index]?.conditions ?? 0
    }

    func shape(of index: UInt16) -> ConditionFunctionShape? {
        shapes[index]
    }

    /// Conditions whose function index the registry can evaluate.
    func implementedCount(in registry: ConditionFunctionRegistry) -> Int {
        registry.indices.reduce(0) { $0 + conditions(of: $1) }
    }

    /// Implemented share of all conditions, 0 when nothing was swept.
    func coverageFraction(in registry: ConditionFunctionRegistry) -> Double {
        total == 0 ? 0 : Double(implementedCount(in: registry)) / Double(total)
    }

    /// Every implemented function with the traffic it carries, hottest first.
    func implementedCounts(
        in registry: ConditionFunctionRegistry
    ) -> [(function: ConditionFunction, conditions: Int)] {
        registry.sortedFunctions()
            .map { ($0, conditions(of: $0.index)) }
            .sorted { ($0.1, $1.0.index) > ($1.1, $0.0.index) }
    }

    /// Unimplemented indices ranked by traffic, ties broken by index so the
    /// order is stable across runs.
    func rankedUnimplemented(
        in registry: ConditionFunctionRegistry
    ) -> [(index: UInt16, conditions: Int)] {
        shapes
            .filter { registry[$0.key] == nil }
            .map { (index: $0.key, conditions: $0.value.conditions) }
            .sorted { ($0.conditions, $1.index) > ($1.conditions, $0.index) }
    }
}
