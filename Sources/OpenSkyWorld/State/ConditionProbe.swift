// Asks one condition function directly, for inspection panels. The comparison is `>= 0`
// and the run-on is the subject, set once here so two panels agree on "current value".
// Returns the value or why there is none. See docs/engine/conditions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated public enum ConditionProbe: Sendable {
    /// Runs one function against `context` and answers with its value.
    ///
    /// - Returns: the left-hand side the function computed, or the
    ///   machine-readable reason it could not.
    public static func value(
        of functionIndex: UInt16,
        parameter1: UInt32 = 0,
        parameter2: UInt32 = 0,
        in context: ConditionContext,
        registry: ConditionFunctionRegistry = .standard
    ) -> Result<Float, ConditionFailure> {
        guard let function = registry[functionIndex] else {
            return .failure(.unknownFunction(functionIndex))
        }
        var call = ConditionCall(
            condition: Condition(
                probingFunction: functionIndex,
                parameter1: parameter1,
                parameter2: parameter2
            ),
            context: context
        )
        return function.body(&call)
    }

    /// The same run, spelled for a readout: the value, or the failure's reason
    /// in the words `RuntimeStateConditionRunner` already uses everywhere else.
    public static func text(
        of functionIndex: UInt16,
        parameter1: UInt32 = 0,
        parameter2: UInt32 = 0,
        in context: ConditionContext,
        registry: ConditionFunctionRegistry = .standard
    ) -> String {
        switch value(
            of: functionIndex,
            parameter1: parameter1,
            parameter2: parameter2,
            in: context,
            registry: registry
        ) {
        case let .success(value): RuntimeStateNumberText.text(value)
        case let .failure(failure): RuntimeStateConditionRunner.describe(failure)
        }
    }
}
