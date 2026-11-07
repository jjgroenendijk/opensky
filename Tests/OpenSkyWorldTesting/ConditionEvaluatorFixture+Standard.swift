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
        try ConditionEvaluator(context: populatedContext(clock: clock), tally: tally)
    }
}
