// The bribe and intimidation defaults, as <https://ck.uesp.net/wiki/Category:Settings>
// lists them, and what the confidence table does at its two ends.

@testable import OpenSkyGameData
import Testing

struct SpeechCheckSettingsTests {
    private let settings = SpeechCheckSettings.fallback

    private func check(confidence: Float) -> SpeechCheckActors {
        SpeechCheckActors(
            playerLevel: 5, playerSpeech: 15, npcLevel: 40, npcSpeech: 60,
            npcMorality: 0, npcConfidence: confidence
        )
    }

    @Test func theDefaultsAreTheGamesOwn() {
        #expect(settings.bribeNPCLevelMult == 0.1)
        #expect(settings.intimidateSpeechcraftCurve == 1.5)
        #expect(settings.intimidateConfidenceMults == [0, 0.5, 1, 1.5, 100])
    }

    /// A coward yields even to a weak player; a foolhardy actor does not.
    @Test func confidenceDecidesTheEnds() {
        #expect(settings.intimidates(check(confidence: 0)))
        #expect(!settings.intimidates(check(confidence: 4)))
    }

    /// The NPC's level costs a tenth of a level each, not a whole one.
    @Test func theNPCLevelWeighsATenth() {
        let low = settings.bribeAmount(check(confidence: 2))
        var richer = check(confidence: 2)
        richer.npcLevel += 10
        let next = settings.bribeAmount(richer)
        var equal = check(confidence: 2)
        equal.playerLevel += 1
        #expect(next == settings.bribeAmount(equal))
        #expect(next > low)
    }
}
