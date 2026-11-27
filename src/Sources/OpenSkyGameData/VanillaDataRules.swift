// The part of the vanilla data rules that needs more than a lookup: a condition list that
// can never pass (docs/tools/headless-sweeps.md, "Rule sweep").

import Foundation
public import OpenSkyFormatsESM

nonisolated public enum VanillaDataRules {
    /// True when the list asks one function, on one subject and with the same parameters,
    /// for two different constant answers. A list with an OR in it is never judged.
    public static func contradicts(_ conditions: [Condition]) -> Bool {
        guard !conditions.contains(where: { $0.flags.contains(.or) }) else { return false }
        struct Asked: Hashable {
            let function: UInt16, runOn: String, reference: UInt32, first: UInt32, second: UInt32
        }
        var equal: [Asked: Float] = [:]
        var notEqual: [Asked: Set<Float>] = [:]
        for condition in conditions {
            guard case let .value(value) = condition.comparisonValue else { continue }
            let asked = Asked(
                function: condition.functionIndex, runOn: "\(condition.runOn)",
                reference: condition.reference.rawValue,
                first: condition.parameter1.rawValue, second: condition.parameter2.rawValue
            )
            switch condition.comparison {
            case .equal:
                if let other = equal[asked], other != value {
                    return true
                }
                equal[asked] = value
            case .notEqual:
                notEqual[asked, default: []].insert(value)
            default:
                continue
            }
        }
        return equal.contains { notEqual[$0.key]?.contains($0.value) == true }
    }
}
