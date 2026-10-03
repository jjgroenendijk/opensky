// IsTorchOut, IsShieldOut, and IsChild through the real evaluator. Idle markers
// test the first two, so an unobserved hand must fail with a reason, not 0.

import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyConditions
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import OpenSkyWorldTesting
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

    @Test func isChildReadsTheRaceFlag() throws {
        let child = Self.state(hand: .nothing, isChild: true)
        #expect(try Self.outcome(Self.isChild, equals: 1, state: child) == .true)
        #expect(try Self
            .outcome(Self.isChild, equals: 0, state: Self.state(hand: .nothing)) == .true)
    }
}
