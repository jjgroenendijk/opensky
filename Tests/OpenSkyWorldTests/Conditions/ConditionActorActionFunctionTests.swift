// The combat-action condition functions through the real evaluator: each reads
// `ActorActionFacts`, and an actor with no observed action fails with a reason.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct ConditionActorActionFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)

    private static func value(
        _ function: UInt16, equals value: Float, action: ActorActionFacts?
    ) throws -> ConditionOutcome {
        var state = ActorConditionState(
            current: ActorValues(repeating: 100), maximums: ActorValues(repeating: 100),
            weaponDrawState: .drawn
        )
        state.action = action
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.actors = ActorStateResolution(states: [subject: state])
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: function, 0, value
        ))
    }

    @Test func aSwingIsAnAttackInTheSwingState() throws {
        let swing = ActorActionFacts(attackState: .swing)
        #expect(try Self.value(672, equals: 1, action: swing) == .true)
        #expect(try Self.value(574, equals: 2, action: swing) == .true)
        #expect(try Self.value(673, equals: 0, action: swing) == .true)
        #expect(try Self.value(672, equals: 0, action: .still) == .true)
    }

    @Test func guardStaggerAndFleeAreReadFromTheFacts() throws {
        let guarding = ActorActionFacts(isBlocking: true)
        #expect(try Self.value(569, equals: 1, action: guarding) == .true)
        #expect(try Self.value(0, equals: 1, action: guarding) == .true)
        #expect(try Self
            .value(701, equals: 1, action: ActorActionFacts(isStaggered: true)) == .true)
        #expect(try Self.value(329, equals: 1, action: ActorActionFacts(isFleeing: true)) == .true)
        #expect(try Self.value(702, equals: 0, action: .still) == .true)
        #expect(try Self.value(725, equals: 0, action: .still) == .true)
    }

    @Test func anUnobservedActionFailsWithAReason() throws {
        #expect(try Self.value(569, equals: 0, action: nil).failures == [.unavailableActorState])
    }

    @Test func aDrawnWeaponIsWeaponOrMagicOut() throws {
        #expect(try Self.value(101, equals: 1, action: .still) == .true)
    }

    @Test func theCombatTargetIsReadThroughTheRunOn() throws {
        let target = ConditionEvaluatorFixture.key(ConditionEvaluatorFixture.targetFormID)
        let file = try KeywordFixture.plugin(keywords: [
            KeywordFixture.recordBytes(formID: 0x35D59, editorID: "ActorTypeDragon")
        ])
        let health = ActorValues(repeating: 100)
        var fighter = ActorConditionState(current: health, maximums: health)
        fighter.combatTarget = target
        var dragon = ActorConditionState(current: health, maximums: health)
        dragon.raceKeywords = [FormID(0x35D59)]
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.actors = ActorStateResolution(states: [Self.subject: fighter, target: dragon])
        context.data = ConditionDataResolution(
            keywords: KeywordStore(plugins: [("Skyrim.esm", file)]), sourcePlugin: "Skyrim.esm"
        )
        var evaluator = ConditionEvaluator(context: context)
        let targetID = ConditionEvaluatorFixture.targetFormID
        #expect(try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: 513, 0, 1, parameter1: targetID
        )) == .true)
        #expect(try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: 707, 0, 1, parameter1: 0x35D59
        )) == .true)
    }
}
