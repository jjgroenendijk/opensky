// IsTorchOut, IsShieldOut, and IsChild through the real evaluator. Idle markers
// test the first two, so an unobserved hand must fail with a reason, not 0.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct ConditionActorBodyFunctionTests {
    private static let isTorchOut: UInt16 = 102
    private static let isShieldOut: UInt16 = 103
    private static let isChild: UInt16 = 365
    private static let subject = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)

    private static func outcome(
        _ function: UInt16,
        equals value: Float,
        state: ActorConditionState
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.actors = ActorStateResolution(states: [subject: state])
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: function, 0, value
        ))
    }

    private static func state(
        hand: ActorLeftHandOut?,
        isChild: Bool = false
    ) -> ActorConditionState {
        ActorConditionState(
            current: ActorValues(repeating: 100), maximums: ActorValues(repeating: 100),
            isChild: isChild, leftHandOut: hand
        )
    }

    @Test func theLeftHandAnswersTorchAndShield() throws {
        #expect(try Self
            .outcome(Self.isTorchOut, equals: 1, state: Self.state(hand: .torch)) == .true)
        #expect(try Self
            .outcome(Self.isShieldOut, equals: 0, state: Self.state(hand: .torch)) == .true)
        #expect(try Self
            .outcome(Self.isShieldOut, equals: 1, state: Self.state(hand: .shield)) == .true)
        #expect(try Self
            .outcome(Self.isTorchOut, equals: 0, state: Self.state(hand: .nothing)) == .true)
    }

    @Test func anUnobservedHandFailsWithAReason() throws {
        let outcome = try Self.outcome(Self.isTorchOut, equals: 0, state: Self.state(hand: nil))
        #expect(outcome.failures == [.unavailableActorState])
    }

    @Test func getIsRaceComparesTheActorsRace() throws {
        var state = Self.state(hand: .nothing)
        state.race = FormID(0x13746)
        let nord = try ConditionEvaluatorFixture.comparing(
            functionIndex: 69, 0, 1, parameter1: 0x13746
        )
        let other = try ConditionEvaluatorFixture.comparing(
            functionIndex: 69, 0, 1, parameter1: 0x13740
        )
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.actors = ActorStateResolution(states: [Self.subject: state])
        var evaluator = ConditionEvaluator(context: context)
        #expect(evaluator.evaluate(nord) == .true)
        #expect(evaluator.evaluate(other).isTrue == false)
        state.race = nil
        context.actors = ActorStateResolution(states: [Self.subject: state])
        evaluator = ConditionEvaluator(context: context)
        #expect(evaluator.evaluate(nord).failures == [.unavailableActorState])
    }

    @Test func noActorIsInAPairedAnimationOrFlying() throws {
        let state = Self.state(hand: .nothing)
        #expect(try Self.outcome(313, equals: 0, state: state) == .true)
        #expect(try Self.outcome(594, equals: 0, state: state) == .true)
    }

    @Test func isUndeadReadsTheRaceKeyword() throws {
        let file = try KeywordFixture.plugin(keywords: [
            KeywordFixture.recordBytes(formID: 0x13796, editorID: "ActorTypeUndead"),
            KeywordFixture.recordBytes(formID: 0x13794, editorID: "ActorTypeNPC")
        ])
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.data = ConditionDataResolution(
            keywords: KeywordStore(plugins: [("Skyrim.esm", file)]), sourcePlugin: "Skyrim.esm"
        )
        func undead(_ keywords: [FormID]?) -> ConditionOutcome {
            var state = Self.state(hand: .nothing)
            state.raceKeywords = keywords
            context.actors = ActorStateResolution(states: [Self.subject: state])
            var evaluator = ConditionEvaluator(context: context)
            return (try? evaluator.evaluate(ConditionEvaluatorFixture.comparing(
                functionIndex: 715, 0, 1
            ))) ?? .false
        }
        #expect(undead([FormID(0x13796)]) == .true)
        #expect(undead([FormID(0x13794)]).isTrue == false)
        #expect(undead(nil).failures == [.unavailableActorState])
    }

    @Test func permanentValueSkipsDamageAndTemporaryModifiers() throws {
        var state = Self.state(hand: .nothing)
        state.general[24] = ActorValueEntry(base: 50, permanent: 10, temporary: 5, damage: -3)
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.actors = ActorStateResolution(states: [Self.subject: state])
        var evaluator = ConditionEvaluator(context: context)
        #expect(try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: 494, 0, 60, parameter1: 24
        )) == .true)
    }

    @Test func isChildReadsTheRaceFlag() throws {
        let child = Self.state(hand: .nothing, isChild: true)
        #expect(try Self.outcome(Self.isChild, equals: 1, state: child) == .true)
        #expect(try Self
            .outcome(Self.isChild, equals: 0, state: Self.state(hand: .nothing)) == .true)
    }

    @Test func sexAndRaceReadTheActorAndThePlayer() throws {
        var npc = Self.state(hand: .nothing)
        npc.isFemale = true
        var player = Self.state(hand: .nothing)
        player.isFemale = false
        player.race = FormID(0x13746)
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.actors = ActorStateResolution(states: [Self.subject: npc, .player: player])
        var evaluator = ConditionEvaluator(context: context)
        let isSex = { (index: UInt16, sex: UInt32) in
            try ConditionEvaluatorFixture.comparing(functionIndex: index, 0, 1, parameter1: sex)
        }
        #expect(try evaluator.evaluate(isSex(70, 1)) == .true)
        #expect(try evaluator.evaluate(isSex(131, 0)) == .true)
        #expect(try evaluator.evaluate(isSex(70, 7)).failures == [.unresolvedParameter(70)])
        #expect(try evaluator.evaluate(isSex(130, 0x13746)) == .true)
        npc.isFemale = nil
        context.actors = ActorStateResolution(states: [Self.subject: npc])
        evaluator = ConditionEvaluator(context: context)
        #expect(try evaluator.evaluate(isSex(70, 1)).failures == [.unavailableActorState])
    }

    @Test func combatHealthAndSneakReadTheState() throws {
        var state = ActorConditionState(
            current: ActorValues(health: 25, magicka: 100, stamina: 100),
            maximums: ActorValues(repeating: 100), combatActivity: .searching
        )
        #expect(try Self.outcome(289, equals: 1, state: state) == .true)
        #expect(try Self.outcome(430, equals: 0.25, state: state) == .true)
        #expect(try Self.outcome(286, equals: 0, state: state).failures
            == [.unavailableActorState])
        state.isSneaking = true
        #expect(try Self.outcome(286, equals: 1, state: state) == .true)
        state.isDead = true
        #expect(try Self.outcome(289, equals: 0, state: state) == .true)
    }
}
