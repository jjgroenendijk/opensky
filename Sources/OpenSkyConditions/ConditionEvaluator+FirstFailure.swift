// Names what made a condition list false, for a readout such as a crafting verdict.
// It follows the same OR grouping as `evaluate(_:)`.

import Foundation
import OpenSkyFormatsESM

nonisolated extension ConditionEvaluator {
    /// The first condition of the first false OR group, or nil when the list is true.
    public mutating func firstFailure(in conditions: [Condition]) -> Condition? {
        var group: [Condition] = []
        var passed = false
        for (index, condition) in conditions.enumerated() {
            group.append(condition)
            passed = evaluate(condition).isTrue || passed
            let closesGroup = !condition.flags.contains(.or) || index == conditions.count - 1
            guard closesGroup else { continue }
            if !passed {
                return group.first
            }
            group = []
            passed = false
        }
        return nil
    }

    /// The Creation Kit name of `condition`'s function, or its CK number when unknown.
    public func functionName(of condition: Condition) -> String {
        let number = Int(condition.functionIndex) + ConditionFunctionRegistry.creationKitOffset
        return registry[condition.functionIndex]?.name ?? "function \(number)"
    }
}
