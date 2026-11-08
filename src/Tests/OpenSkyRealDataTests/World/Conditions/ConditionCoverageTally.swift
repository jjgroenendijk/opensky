// Per-function coverage tally for the real-data CTDA sweep. It measures how
// much condition traffic `ConditionFunctionRegistry.standard` can evaluate, and
// the on-disk shape of each function index. Counts are aggregate only, so the
// report written to gitignored `.logs/` extracts no record.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM

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

    /// Decodes every CTDA in every plugin; a field that fails to decode is skipped.
    static func sweep(plugins: [(name: String, file: ESMFile)]) -> Self {
        var coverage = Self()
        for plugin in plugins {
            ESMWalk.forEachRecord(in: plugin.file) { record in
                guard let fields = try? record.fields() else { return true }
                var list = ConditionList()
                for field in fields {
                    _ = try? list.decode(field: field)
                }
                for condition in list.conditions {
                    coverage.record(condition)
                }
                return true
            }
        }
        return coverage
    }

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
