// The expression a face holds from fear, combat, the spoken line, and the mood.

@testable import OpenSkyActorPresentation
import OpenSkyFormatsESM
import Testing

struct FacialMoodRulesTests {
    @Test func fearWinsOverEverythingElse() {
        let input = FaceMoodInput(isFleeing: true, isInCombat: true, mood: 3)
        #expect(FacialMoodRules.goal(input, speaking: (.happy, 50)) == ["DialogueFear": 1])
    }

    @Test func combatShowsCombatAngerOrDialogueAngerWhileSpeaking() {
        let input = FaceMoodInput(isInCombat: true)
        #expect(FacialMoodRules.goal(input, speaking: nil) == ["CombatAnger": 1])
        #expect(FacialMoodRules.goal(input, speaking: (.sad, 40)) == ["DialogueAnger": 1])
        let swinging = FaceMoodInput(isAttacking: true)
        #expect(FacialMoodRules.goal(swinging, speaking: nil) == ["CombatAnger": 1])
    }

    @Test func aSpokenLineShowsItsEmotionAtItsValue() {
        #expect(FacialMoodRules.goal(.calm, speaking: (.sad, 40)) == ["DialogueSad": 0.4])
    }

    @Test func aQuietFaceRestsAtHalfItsMood() {
        #expect(FacialMoodRules.goal(FaceMoodInput(mood: 3), speaking: nil) == ["MoodHappy": 0.5])
        #expect(FacialMoodRules.goal(FaceMoodInput(mood: 9), speaking: nil).isEmpty)
        #expect(FacialMoodRules.goal(.calm, speaking: nil).isEmpty, "no MoodNeutral shape")
    }
}
