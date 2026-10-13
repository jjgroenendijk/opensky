// How often the data uses each condition function, so `openskycli gaps` can rank the
// functions no registry entry answers. Counts only; no record is kept.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct ConditionFunctionCensus: Equatable, Sendable {
    /// Stored function index -> conditions that use it.
    public private(set) var counts: [UInt16: Int] = [:]
    public private(set) var total = 0

    public init() {}

    public mutating func record(_ condition: Condition) {
        total += 1
        counts[condition.functionIndex, default: 0] += 1
    }

    /// Every CTDA in `fields`. A field that does not decode is not counted.
    public mutating func record(fields: [ESMField]) {
        var list = ConditionList()
        for field in fields {
            _ = try? list.decode(field: field)
        }
        for condition in list.conditions {
            record(condition)
        }
    }

    /// Functions `registry` cannot evaluate, most used first, ties by index.
    public func missing(
        in registry: ConditionFunctionRegistry
    ) -> [(index: UInt16, count: Int)] {
        counts
            .filter { registry[$0.key] == nil }
            .map { (index: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.index) > ($1.count, $0.index) }
    }
}
