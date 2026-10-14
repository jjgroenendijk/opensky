// Script variables, scenes, cells, weather, and inventory facts through the
// real evaluator. Each function answers from its seam and fails with a reason
// when the seam is empty.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyDialogueInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyInventoryInterface
@testable import OpenSkyWorld
import Testing

struct ConditionWorldFactFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let target = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.targetFormID)

    private static func evaluate(
        _ function: UInt16,
        equals value: Float,
        parameter1: UInt32 = 0,
        parameter2: UInt32 = 0,
        parameter2Name: String? = nil,
        _ change: (inout ConditionContext) -> Void
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        change(&context)
        var condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern, functionIndex: function,
            parameter1: parameter1, parameter2: parameter2
        )
        condition.parameter2Name = parameter2Name
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(condition)
    }

    @Test func getVMScriptVariableReadsTheParameterObject() throws {
        let variables = ScriptVariableResolution(values: [Self.target: ["::ballin_var": 1]])
        let found = try Self.evaluate(
            630, equals: 1, parameter1: ConditionEvaluatorFixture.targetFormID,
            parameter2Name: "::bAllIn_var"
        ) { $0.scriptVariables = variables }
        #expect(found == .true)
        let empty = try Self.evaluate(
            630, equals: 1, parameter1: ConditionEvaluatorFixture.targetFormID,
            parameter2Name: "::bAllIn_var"
        ) { _ in }
        #expect(empty.failures == [.unavailableData(.scriptVariable)])
    }

    @Test func sceneFunctionsReadThePlayingScenes() throws {
        let scene: UInt32 = 0x0300
        let scenes = SceneConditionResolution(
            playing: [FormID(scene): [4]], actors: [Self.subject]
        )
        let set = { (context: inout ConditionContext) in context.scenes = scenes }
        #expect(try Self.evaluate(248, equals: 1, parameter1: scene, set) == .true)
        #expect(try Self.evaluate(248, equals: 0, parameter1: 0x0301, set) == .true)
        #expect(try Self.evaluate(550, equals: 1, parameter1: scene, parameter2: 4, set) == .true)
        #expect(try Self.evaluate(550, equals: 0, parameter1: scene, parameter2: 5, set) == .true)
        #expect(try Self.evaluate(590, equals: 1, set) == .true)
        #expect(try Self.evaluate(590, equals: 1) { _ in }.failures == [.unavailableData(.scene)])
    }

    @Test func cellFunctionsCompareTheLoadedCell() throws {
        let tavern = ReferenceCell(cell: FormID(0x0400), worldspace: nil)
        let outside = ReferenceCell(cell: FormID(0x0401), worldspace: FormID(0x0500))
        let data = { (subject: ReferenceCell, target: ReferenceCell) in
            { (context: inout ConditionContext) in
                context.data = ConditionDataResolution(
                    cells: [Self.subject: subject, Self.target: target]
                )
            }
        }
        #expect(try Self.evaluate(67, equals: 1, parameter1: 0x0400, data(tavern, outside))
            == .true)
        #expect(try Self.evaluate(310, equals: 0, parameter1: 0x0500, data(tavern, outside))
            == .true)
        #expect(try Self.evaluate(310, equals: 1, parameter1: 0x0500, data(outside, tavern))
            == .true)
        let target = ConditionEvaluatorFixture.targetFormID
        #expect(try Self.evaluate(32, equals: 1, parameter1: target, data(tavern, tavern))
            == .true)
        #expect(try Self.evaluate(32, equals: 0, parameter1: target, data(tavern, outside))
            == .true)
        #expect(try Self.evaluate(67, equals: 1, parameter1: 0x0400) { _ in }.failures
            == [.unavailableData(.cell)])
    }

    @Test func referenceIdentityComparesKeys() throws {
        let subject = ConditionEvaluatorFixture.subjectFormID
        let target = ConditionEvaluatorFixture.targetFormID
        #expect(try Self.evaluate(136, equals: 1, parameter1: subject) { _ in } == .true)
        #expect(try Self.evaluate(136, equals: 0, parameter1: target) { _ in } == .true)
        #expect(try Self.evaluate(353, equals: 0) { _ in } == .true)
        #expect(try Self.evaluate(353, equals: 1) { $0.subject = .player } == .true)
    }

    @Test func weatherFunctionsReadTheClassification() throws {
        let rain = WeatherConditionResolution(weather: FormID(0x0600), precipitation: .rainy)
        let set = { (context: inout ConditionContext) in context.weather = rain }
        #expect(try Self.evaluate(149, equals: 1, parameter1: 0x0600, set) == .true)
        #expect(try Self.evaluate(62, equals: 1, set) == .true)
        #expect(try Self.evaluate(75, equals: 0, set) == .true)
        #expect(try Self.evaluate(266, equals: 0, set) == .true)
        #expect(try Self.evaluate(62, equals: 0) { _ in }.failures == [.unavailableData(.weather)])
    }

    @Test func goldAndEquipmentReadTheInventorySeam() throws {
        let item: UInt32 = 0x0700
        let inventory = InventoryConditionResolution(
            counts: [Self.subject: [ConditionFunctions.goldItem: 250]],
            equipped: [Self.subject: [FormID(item)]]
        )
        let set = { (context: inout ConditionContext) in context.inventory = inventory }
        #expect(try Self.evaluate(48, equals: 250, set) == .true)
        #expect(try Self.evaluate(182, equals: 1, parameter1: item, set) == .true)
        #expect(try Self.evaluate(182, equals: 0, parameter1: 0x0701, set) == .true)
        #expect(try Self.evaluate(182, equals: 1, parameter1: item) { _ in }.failures
            == [.unavailableData(.inventory)])
    }
}
