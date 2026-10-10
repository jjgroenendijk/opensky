// `GetItemCount` and `EPTemperingItemIsEnchanted` through the whole-game registry,
// and the first failing group that a crafting verdict names.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyInventoryInterface
@testable import OpenSkyWorld
import Testing

struct ConditionInventoryFunctionTests {
    private static let getItemCount: UInt16 = 47
    private static let hasPerk: UInt16 = 448
    private static let ingot: UInt32 = 0x0005_ACE4

    /// `GetItemCount(ingot) >= count` on the subject.
    private static func holds(_ count: Float, isOr: Bool = false) throws -> Condition {
        try ConditionEvaluatorFixture.condition(
            operatorBits: 3,
            flags: isOr ? 0x01 : 0,
            comparisonValue: count.bitPattern,
            functionIndex: getItemCount,
            parameter1: ingot
        )
    }

    private static func evaluator(holding count: Int32?) -> ConditionEvaluator {
        var context = ConditionContext(subject: .player)
        if let count {
            context.inventory = InventoryConditionResolution(
                counts: [.player: [FormID(ingot): count]]
            )
        }
        return ConditionEvaluator(context: context)
    }

    @Test func getItemCountReadsTheSubjectInventory() throws {
        var evaluator = Self.evaluator(holding: 2)
        let enough = try evaluator.evaluate(Self.holds(2))
        let tooFew = try evaluator.evaluate(Self.holds(3))
        var empty = Self.evaluator(holding: 0)
        let none = try empty.evaluate(Self.holds(1))
        #expect(enough.isTrue)
        #expect(!tooFew.isTrue)
        #expect(!none.isTrue)
    }

    @Test func getItemCountWithoutInventoryIsATaggedFailure() throws {
        var evaluator = Self.evaluator(holding: nil)
        let outcome = try evaluator.evaluate(Self.holds(0))
        #expect(outcome.failures == [.unavailableData(.inventory)])
    }

    @Test func firstFailureNamesTheFirstFalseGroup() throws {
        var evaluator = Self.evaluator(holding: 1)
        let perk = try ConditionEvaluatorFixture.comparing(
            functionIndex: Self.hasPerk, 0, 1, parameter1: 0x0001_0000
        )
        let held = try Self.holds(1)
        let passing = evaluator.firstFailure(in: [held])
        let perkFailure = evaluator.firstFailure(in: [held, perk])
        let grouped = try evaluator.firstFailure(in: [Self.holds(5, isOr: true), held])
        let bothFalse = try evaluator.firstFailure(in: [Self.holds(5, isOr: true), Self.holds(6)])
        #expect(passing == nil)
        #expect(perkFailure.map(evaluator.functionName(of:)) == "HasPerk")
        #expect(grouped == nil)
        #expect(bothFalse.map(evaluator.functionName(of:)) == "GetItemCount")
    }

    @Test func temperingAsksWhetherTheImprovedItemIsEnchanted() throws {
        // `EPTemperingItemIsEnchanted != 1`, as the vanilla tempering recipes write it.
        let plainOnly = try ConditionEvaluatorFixture.condition(
            operatorBits: 1, comparisonValue: Float(1).bitPattern, functionIndex: 659
        )
        var context = ConditionContext(subject: .player)
        var unknown = ConditionEvaluator(context: context)
        #expect(unknown.evaluate(plainOnly).failures == [.unavailableData(.inventory)])
        context.tempering = TemperingConditionResolution(isEnchanted: false)
        var plain = ConditionEvaluator(context: context)
        #expect(plain.evaluate(plainOnly).isTrue)
        context.tempering = TemperingConditionResolution(isEnchanted: true)
        var enchanted = ConditionEvaluator(context: context)
        #expect(!enchanted.evaluate(plainOnly).isTrue)
        #expect(enchanted.functionName(of: plainOnly) == "EPTemperingItemIsEnchanted")
    }
}
