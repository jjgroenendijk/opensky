// Condition functions that read script-set state, and the actor gait and record-flag
// reads, through the real evaluator. Indices are raw (the Creation Kit adds 4096).

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyScriptingInterface
@testable import OpenSkyWorld
import Testing

struct ConditionScriptStateFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let location: UInt32 = 0x0400
    private static let keyword: UInt32 = 0x0401

    private static func evaluate(
        _ function: UInt16,
        equals value: Float,
        parameter1: UInt32 = 0,
        parameter2: UInt32 = 0,
        _ change: (inout ConditionContext) -> Void
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        let resolver = FormIDResolver(pluginName: "Skyrim.esm", masters: [])
        context.formIDTranslation = FormIDTranslation(source: resolver, target: resolver)
        change(&context)
        let condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern, functionIndex: function,
            parameter1: parameter1, parameter2: parameter2
        )
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(condition)
    }

    private static func states(
        _ states: [ReferenceKey: ScriptedReferenceState]
    ) -> (inout ConditionContext) -> Void {
        { $0.scriptedState = ScriptedStateConditionResolution(states: states) }
    }

    @Test func flagFunctionsReadTheRunOnsScriptState() throws {
        let ghost = Self.states([Self.subject: ScriptedReferenceState(flags: ["ghost": true])])
        #expect(try Self.evaluate(237, equals: 1, ghost) == .true)
        #expect(try Self.evaluate(244, equals: 0, ghost) == .true)
        let teammate = Self.states([
            Self.subject: ScriptedReferenceState(flags: ["playerTeammate": true])
        ])
        #expect(try Self.evaluate(453, equals: 1, teammate) == .true)
        let unwired = try Self.evaluate(237, equals: 0) { _ in }
        #expect(unwired.failures == [.unavailableData(.scriptState)])
    }

    @Test func locationFunctionsReadTheLocationsScriptState() throws {
        let locationKey = ConditionEvaluatorFixture.key(Self.location)
        let keywordKey = ConditionEvaluatorFixture.key(Self.keyword)
        let state = ScriptedReferenceState(
            flags: ["cleared": true],
            values: [ScriptedStateName.keywordData(keywordKey): 3]
        )
        let set = Self.states([locationKey: state])
        #expect(try Self.evaluate(250, equals: 1, parameter1: Self.location, set) == .true)
        #expect(try Self.evaluate(
            606, equals: 3, parameter1: Self.location, parameter2: Self.keyword, set
        ) == .true)
        // Unset keyword data reads 0, as `GetKeywordData` does.
        #expect(try Self.evaluate(
            606, equals: 0, parameter1: Self.location, parameter2: 0x0402, set
        ) == .true)
        let current = try Self.evaluate(651, equals: 3, parameter1: Self.keyword) { context in
            set(&context)
            context.data = ConditionDataResolution(
                currentLocations: [
                    Self.subject: ResolvedFormID(plugin: "Skyrim.esm", objectID: Self.location)
                ]
            )
        }
        #expect(current == .true)
    }

    @Test func gaitAndRecordFlagsReadTheActorState() throws {
        var state = ActorConditionState(
            current: ActorValues(repeating: 100), maximums: ActorValues(repeating: 100)
        )
        state.isSprinting = true
        state.isSwimming = false
        state.recordFlags = [.essential, .unique]
        let set = { (context: inout ConditionContext) in
            context.actors = ActorStateResolution(states: [Self.subject: state])
        }
        #expect(try Self.evaluate(568, equals: 1, set) == .true)
        #expect(try Self.evaluate(185, equals: 0, set) == .true)
        #expect(try Self.evaluate(354, equals: 1, set) == .true)
        #expect(try Self.evaluate(476, equals: 0, set) == .true)
        #expect(try Self.evaluate(641, equals: 1, set) == .true)
        state.recordFlags = nil
        let unknown = try Self.evaluate(354, equals: 0) { context in
            context.actors = ActorStateResolution(states: [Self.subject: state])
        }
        #expect(unknown.failures == [.unavailableActorState])
    }
}
