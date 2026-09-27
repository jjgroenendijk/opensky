// Asking one condition function directly (issue #474, roadmap item 19.11).
//
// Every other caller of the evaluator has a condition to evaluate: a record
// carried it, and the comparison and the run-on came with it. An inspection
// surface has the opposite problem — it knows which *function* it wants to show
// and has to invent the rest — and inventing it at each call site would let two
// panels disagree about what "the current value" of a function means.
//
// So the invented parts live here, once: the comparison is `>= 0`, which every
// documented return satisfies, and the run-on is the subject. What comes back
// is the function's own value or the reason it has none, which is what a
// readout wants and what `ConditionOutcome` deliberately flattens away.
//
// Documented in docs/formats/conditions.md.

import Foundation

nonisolated enum ConditionProbe {
    /// Runs one function against `context` and answers with its value.
    ///
    /// - Returns: the left-hand side the function computed, or the
    ///   machine-readable reason it could not.
    static func value(
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
    static func text(
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
