// Which speech challenge a said line wins, read from the condition that gates it.

import Foundation
@testable import OpenSkyDialogue
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import Testing

struct SpeechChallengeTests {
    private func info(_ condition: Data) throws -> TopicInfo {
        try DialogueFixture.info(condition)
    }

    @Test func successConditionsNameTheChallenge() throws {
        let bribe = try info(DialogueFixture.condition(functionIndex: 654, comparisonValue: 1))
        let threat = try info(DialogueFixture.condition(functionIndex: 655, comparisonValue: 1))
        let persuade = try info(DialogueFixture.condition(
            functionIndex: 14, operatorBits: 3, comparisonValue: 50, parameter1: 17
        ))
        #expect(SpeechChallenge.won(by: bribe) == .bribe)
        #expect(SpeechChallenge.won(by: threat) == .intimidate)
        #expect(SpeechChallenge.won(by: persuade) == .persuade)
        #expect(SpeechChallenge.won(by: persuade)?.eventCode == "FLAT")
    }

    /// A failed intimidation tests the function against 0, and wins nothing.
    @Test func failureAndPlainLinesWinNothing() throws {
        let failed = try info(DialogueFixture.condition(functionIndex: 655, comparisonValue: 0))
        let plain = try info(DialogueFixture.isSpeaker(0x1234))
        #expect(SpeechChallenge.won(by: failed) == nil)
        #expect(SpeechChallenge.won(by: plain) == nil)
    }
}
