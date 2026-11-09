// The evaluator over the whole-game registry, which `OpenSkyWorld` owns.

@testable public import OpenSkyConditions
public import OpenSkyFeaturesTesting
import OpenSkyWorldConditions
@testable public import OpenSkyWorldState

extension ConditionEvaluatorFixture {
    /// Evaluator over `populatedContext(clock:)`.
    public static func evaluator(
        clock: GameClock? = nil,
        tally: ConditionTally = ConditionTally()
    ) throws -> ConditionEvaluator {
        try ConditionEvaluator(
            context: populatedContext(clock: clock).using(.standard),
            tally: tally
        )
    }

    /// `functionIndex <comparison> value` under `runOn`, over the whole-game registry,
    /// with the tally it left.
    public static func evaluateStandard(
        _ functionIndex: UInt16,
        _ comparison: UInt8,
        _ value: Float,
        runOn: UInt32 = 0,
        parameter1: UInt32 = 0,
        context: ConditionContext
    ) throws -> (outcome: ConditionOutcome, tally: ConditionTally) {
        var evaluator = ConditionEvaluator(context: context.using(.standard))
        let outcome = try evaluator.evaluate(comparing(
            functionIndex: functionIndex,
            comparison,
            value,
            runOn: runOn,
            parameter1: parameter1
        ))
        return (outcome, evaluator.tally)
    }
}
