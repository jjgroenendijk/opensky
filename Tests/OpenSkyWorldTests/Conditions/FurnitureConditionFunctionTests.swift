// The furniture condition functions read how the subject uses a furniture marker,
// and fail with the furniture domain when no furniture seam is set.

@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
@testable import OpenSkyWorld
import Testing

struct FurnitureConditionFunctionTests {
    private static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0654ED)

    private static func returns(
        _ function: UInt16, _ parameter1: UInt32 = 0, value: Float,
        context: ConditionContext, name: String? = nil
    ) throws -> ConditionOutcome {
        var condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern, functionIndex: function, parameter1: parameter1
        )
        condition.parameter1Name = name
        var context = context
        context.subject = actor
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(condition)
    }

    private static func seated(_ state: FurnitureUse.SitState) -> ConditionContext {
        var context = ConditionContext()
        context.furniture = FurnitureConditionResolution(
            uses: [actor: FurnitureUse(
                sitState: state, animationType: 1, entry: 0x40000, furniture: nil
            )],
            isAvailable: true
        )
        return context
    }

    @Test func getSittingReadsTheSitState() throws {
        #expect(try Self.returns(159, value: 2, context: Self.seated(.readyToSit)).isTrue)
        #expect(try Self.returns(159, value: 3, context: Self.seated(.sitting)).isTrue)
        var standing = ConditionContext()
        standing.furniture.isAvailable = true
        #expect(try Self.returns(159, value: 0, context: standing).isTrue)
    }

    @Test func theMarkerTypeAndEntryMatchTheirParameter() throws {
        let context = Self.seated(.readyToSit)
        #expect(try Self.returns(613, 1, value: 1, context: context).isTrue)
        #expect(try !Self.returns(613, 4, value: 1, context: context).isTrue)
        #expect(try Self.returns(614, 0x40000, value: 1, context: context).isTrue)
        #expect(try !Self.returns(614, 0x20000, value: 1, context: context).isTrue)
        #expect(try Self.returns(631, value: 0, context: context).isTrue)
        #expect(try !Self.returns(644, 1, value: 1, context: context).isTrue)
        #expect(try Self.returns(644, 1, value: 1, context: Self.seated(.sitting)).isTrue)
    }

    @Test func noFurnitureSeamFailsHonestly() throws {
        let outcome = try Self.returns(159, value: 0, context: ConditionContext())
        #expect(outcome.failures == [.unavailableData(.furniture)])
    }

    @Test func aGraphVariableReadsZeroForAnActorWithoutAGraph() throws {
        var context = ConditionContext()
        #expect(try Self.returns(675, value: 0, context: context, name: "bInJumpState")
            .failures == [.unavailableData(.graphVariable)])
        context.graphVariables.values[Self.actor] = [:]
        #expect(try Self.returns(675, value: 0, context: context, name: "bInJumpState").isTrue)
        context.graphVariables.values[Self.actor] = ["bInJumpState": 1]
        #expect(try !Self.returns(675, value: 0, context: context, name: "bInJumpState").isTrue)
    }
}
