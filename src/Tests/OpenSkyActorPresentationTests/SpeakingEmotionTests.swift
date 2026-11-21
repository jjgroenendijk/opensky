// The speaking emotion value: the roll range, when a roll happens, and the fall
// after the line.

@testable import OpenSkyActorPresentation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import Testing

@MainActor
struct SpeakingEmotionTests {
    private let settings = SpeakingEmotionSettings()

    @Test func theRangeClampsTheHighEndOnlyWhenTheLowEndIsNotBelowZero() {
        #expect(SpeakingEmotion(base: 60).range(settings) == 0 ..< 100)
        var wide = settings
        wide.minDeltaPercent = 150
        #expect(SpeakingEmotion(base: 60).range(wide) == 0 ..< 120)
        var narrow = settings
        narrow.minDeltaPercent = 50
        narrow.maxDeltaPercent = 50
        #expect(SpeakingEmotion(base: 40).range(narrow) == 20 ..< 60)
    }

    @Test func aRollNeedsTheListenValueAndARunOutTimer() {
        var loud = SpeakingEmotion(base: 80)
        loud.speak(elapsed: 10, settings: settings) { 0.5 }
        #expect(loud.value == 80)

        var neutral = SpeakingEmotion(base: 50)
        neutral.speak(elapsed: 0, settings: settings) { 0.9 }
        #expect(neutral.value == 90)
        #expect(neutral.timer == 1.5)
        neutral.speak(elapsed: 10, settings: settings) { 0.1 }
        #expect(neutral.value == 90)
    }

    @Test func aRollBackToTheListenValueWaitsForTheTimer() {
        var emotion = SpeakingEmotion(base: 50)
        emotion.speak(elapsed: 0, settings: settings) { 0.5 }
        #expect(emotion.value == 50)
        emotion.speak(elapsed: 1, settings: settings) { 0.2 }
        #expect(emotion.value == 50)
        emotion.speak(elapsed: 1, settings: settings) { 0.2 }
        #expect(emotion.value == 20)
    }

    @Test func afterTheLineAHighValueFallsAndALowOneStays() {
        var high = SpeakingEmotion(base: 75)
        let settled1 = high.settle(settings: settings)
        #expect(settled1)
        #expect(high.value == 65)
        let settled2 = high.settle(settings: settings)
        #expect(settled2)
        let settled3 = high.settle(settings: settings)
        #expect(!settled3)
        #expect(high.value == 50)
        var low = SpeakingEmotion(base: 20)
        let settled4 = low.settle(settings: settings)
        #expect(!settled4)
        #expect(low.value == 20)
    }

    @Test func theCoordinatorRollsDuringALineAndDropsItAfterwards() {
        let coordinator = FaceMorphCoordinator()
        coordinator.random = { 0.8 }
        let actor = FormID(0x14)
        coordinator.showEmotion(.happy, value: 50, on: actor, now: 0, seconds: 2)
        coordinator.tick(now: 0)
        coordinator.tick(now: 1)
        #expect(coordinator.emotionValues[actor] == 80)
        coordinator.tick(now: 2)
        #expect(coordinator.emotionValues[actor] == 70)
        coordinator.tick(now: 2.1)
        coordinator.tick(now: 2.2)
        #expect(coordinator.emotionValues[actor] == nil)
        coordinator.showEmotion(.sad, value: 30, on: actor, now: 3)
        coordinator.clearEmotion(on: actor)
        coordinator.tick(now: 3.1)
        #expect(coordinator.emotionValues.isEmpty)
    }

    @Test func thePluginSettingsReplaceTheDefaults() throws {
        let file = try GameSettingFixture.plugin(settings: [
            "fGameplayiSpeakingEmotionMinDeltaChange": .float(20),
            "fGameplayiSpeakingEmotionMaxDeltaChange": .float(40),
            "fGameplaySpeakingEmotionMinChangeValue": .float(3)
        ])
        let resolved = FaceAnimationSettings
            .resolve(store: GameSettingStore(plugins: [("F.esp", file)])).speakingEmotion
        #expect(resolved.minDeltaPercent == 20 && resolved.maxDeltaPercent == 40)
        #expect(resolved.changeSecondsMin == 3)
    }
}
