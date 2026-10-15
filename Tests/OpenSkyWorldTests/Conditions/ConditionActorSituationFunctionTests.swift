// Load, fight-group, speech-check, and menu condition functions through the real
// evaluator. Indices are raw (the Creation Kit adds 4096).

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct ConditionActorSituationFunctionTests {
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)
    private static let target = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.targetFormID)

    private static func actor(
        level: Int = 1, values: [Int32: Float] = [:],
        activity: ActorCombatActivity = .notFighting
    ) -> ActorConditionState {
        let health = ActorValues(repeating: 100)
        return ActorConditionState(
            current: health, maximums: health, combatActivity: activity,
            generalBaseline: values, level: level
        )
    }

    private static func evaluate(
        _ function: UInt16, equals value: Float, parameter1: UInt32 = 0,
        _ change: (inout ConditionContext) -> Void
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        change(&context)
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern, functionIndex: function, parameter1: parameter1
        ))
    }

    @Test func overEncumbranceIsReadAndUnweighedFails() throws {
        var heavy = Self.actor()
        heavy.isOverEncumbered = true
        #expect(try Self.evaluate(734, equals: 1) {
            $0.actors = ActorStateResolution(states: [Self.subject: heavy])
        } == .true)
        #expect(try Self.evaluate(734, equals: 0) {
            $0.actors = ActorStateResolution(states: [Self.subject: Self.actor()])
        }.failures == [.unavailableActorState])
    }

    @Test func fightingNPCsShareOneGroup() throws {
        let fighting = Self.actor(activity: .fighting)
        let states = [Self.subject: fighting, Self.target: fighting, .player: fighting]
        #expect(try Self.evaluate(415, equals: 2) {
            $0.actors = ActorStateResolution(states: states)
        } == .true)
        #expect(try Self.evaluate(415, equals: 0) {
            $0.actors = ActorStateResolution(states: [Self.subject: Self.actor()])
        } == .true)
    }

    @Test func unmodelledReactionsReadZeroForAnActor() throws {
        let set = { (context: inout ConditionContext) in
            context.actors = ActorStateResolution(states: [Self.subject: Self.actor()])
        }
        for function: UInt16 in [645, 697, 247, 305, 274, 642] {
            #expect(try Self.evaluate(function, equals: 0, set) == .true)
        }
    }

    /// The player at level 30 with Speech 50 against a level 10 actor with Speech 20.
    private static func speechContext(
        confidence: Float, gold: Int, _ context: inout ConditionContext
    ) {
        let player = Self.actor(level: 30, values: [SpeechCheckValues.speechcraft: 50])
        let npc = Self.actor(level: 10, values: [
            SpeechCheckValues.speechcraft: 20, SpeechCheckValues.confidence: confidence,
            SpeechCheckValues.morality: 3
        ])
        context.actors = ActorStateResolution(states: [.player: player, Self.subject: npc])
        context.speechChecks = SpeechCheckResolution(settings: .fallback, playerGold: gold)
    }

    @Test func intimidationComparesScarinessAndAFoolhardyActorNeverYields() throws {
        #expect(try Self.evaluate(655, equals: 1) {
            Self.speechContext(confidence: 2, gold: 0, &$0)
        } == .true)
        #expect(try Self.evaluate(655, equals: 0) {
            Self.speechContext(confidence: 4, gold: 0, &$0)
        } == .true)
        #expect(try Self.evaluate(655, equals: 0) { _ in }.failures
            == [.unavailableData(.speech)])
    }

    @Test func aBribeSucceedsWhenThePlayerCanPay() throws {
        let checks = SpeechCheckActors(
            playerLevel: 30, playerSpeech: 50, npcLevel: 10, npcSpeech: 20,
            npcMorality: 3, npcConfidence: 2
        )
        let price = SpeechCheckSettings.fallback.bribeAmount(checks)
        #expect(price > 0)
        #expect(try Self.evaluate(654, equals: 1) {
            Self.speechContext(confidence: 2, gold: Int(price), &$0)
        } == .true)
        #expect(try Self.evaluate(654, equals: 0) {
            Self.speechContext(confidence: 2, gold: Int(price) - 1, &$0)
        } == .true)
    }

    @Test func menuModeAndTheLoadingScreenReadTheInterface() throws {
        let open = { (context: inout ConditionContext) in
            context.menus = MenuConditionResolution(isMenuOpen: true, isLoading: false)
        }
        #expect(try Self.evaluate(36, equals: 1, open) == .true)
        #expect(try Self.evaluate(36, equals: 0, parameter1: 3, open).failures
            == [.unresolvedParameter(36)])
        #expect(try Self.evaluate(358, equals: 0, open) == .true)
        #expect(try Self.evaluate(358, equals: 0) { _ in }.failures == [.unavailableData(.menu)])
    }
}
