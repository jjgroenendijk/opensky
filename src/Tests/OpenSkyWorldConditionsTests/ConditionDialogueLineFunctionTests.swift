// The line an actor says to the player, through the real evaluator: who talks, whether
// it greets, and the response's emotion. Indices are raw (the Creation Kit adds 4096).

import Foundation
@testable import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyWorldConditions
import Testing

struct ConditionDialogueLineFunctionTests {
    private static let speaker = ConditionEvaluatorFixture
        .key(ConditionEvaluatorFixture.subjectFormID)

    private static func evaluate(
        _ function: UInt16, equals value: Float, dialogue: DialogueResolution,
        runOn: UInt32 = 0
    ) throws -> ConditionOutcome {
        var context = try ConditionEvaluatorFixture.populatedContext()
        context.dialogue = dialogue
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.comparing(
            functionIndex: function, 0, value, runOn: runOn
        ))
    }

    @Test func theSpeakerTalksWithItsResponsesEmotion() throws {
        let line = DialogueSpokenLine(
            speaker: Self.speaker, emotion: 1, emotionValue: 50, isGreeting: true
        )
        let dialogue = DialogueResolution(line: line)
        #expect(try Self.evaluate(141, equals: 1, dialogue: dialogue) == .true)
        #expect(try Self.evaluate(123, equals: 1, dialogue: dialogue) == .true)
        #expect(try Self.evaluate(434, equals: 1, dialogue: dialogue) == .true)
        #expect(try Self.evaluate(435, equals: 50, dialogue: dialogue) == .true)
        // The target (run-on 1) says nothing.
        #expect(try Self.evaluate(141, equals: 0, dialogue: dialogue, runOn: 1) == .true)
        #expect(try Self.evaluate(141, equals: 0, dialogue: DialogueResolution()) == .true)
    }

    @Test func noDialogueSeamFailsHonestly() throws {
        #expect(try Self.evaluate(141, equals: 0, dialogue: .empty).failures
            == [.unavailableDialogue])
    }
}
