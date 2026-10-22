// The automatic face: dialogue emotions map to the expression TRI's names, blinks follow
// the blink settings, and the eyes drift inside the emotion's range.

@testable import OpenSkyActorPresentation
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import Testing

@MainActor
struct FacialExpressionCoreTests {
    @Test func emotionsUseTheExpressionTargetNames() {
        #expect(FacialExpressionCore.emotionWeights(.anger, value: 50) == ["DialogueAnger": 0.5])
        #expect(FacialExpressionCore.emotionWeights(.happy, value: 250) == ["DialogueHappy": 1])
        #expect(FacialExpressionCore.emotionWeights(.neutral, value: 80).isEmpty)
    }

    @Test func aBlinkClosesOverTheDownTimeAndOpensOverTheUpTime() {
        let settings = FaceAnimationSettings.vanilla
        func closed(_ elapsed: Float) -> Float {
            FacialExpressionCore.blinkClosure(elapsed: elapsed, settings: settings)
        }
        #expect(abs(closed(0.02) - 0.5) < 0.001)
        #expect(abs(closed(0.04) - 1) < 0.001)
        #expect(abs(closed(0.11) - 0.5) < 0.001)
        #expect(closed(0.18) == 0)
        #expect(closed(-1) == 0)
    }

    @Test func eyesDriftInsideTheEmotionsRange() {
        let settings = FaceAnimationSettings.vanilla
        let range = settings.eyeRange(for: .sad)
        #expect(range == settings.eyeRanges["Sad"])
        #expect(settings.eyeRange(for: .puzzled) == settings.eyeRanges["Neutral"])
        for step in 0 ..< 20 {
            let offset = FacialExpressionCore.eyeOffset(
                at: Float(step), seed: 3, range: range, interval: 2
            )
            #expect(offset.yaw >= range.headingMin && offset.yaw <= range.headingMax)
            #expect(offset.pitch <= -0.015 && offset.pitch >= -0.05)
        }
        let weights = FacialExpressionCore.eyeWeights(
            HeadLook(yaw: 0.1, pitch: -0.05), settings: settings
        )
        #expect(abs((weights["LookLeft"] ?? 0) - 0.1 * 180 / .pi / 28) < 0.0001)
        #expect(abs((weights["LookDown"] ?? 0) - 0.05 * 180 / .pi / 20) < 0.0001)
        #expect(weights["LookRight"] == nil && weights["LookUp"] == nil)
    }

    @Test func aSpeakingEmotionEasesInAtTheChangeSpeed() {
        let settings = FaceAnimationSettings.vanilla
        let rate = settings.speakingEmotionRate(rolls: (0.3, 0.7))
        #expect(abs(rate - 1 / 1.5) < 0.0001, "100 points over 1.5 seconds")
        let half = FacialExpressionCore.ease([:], toward: ["DialogueHappy": 1], step: 0.5)
        #expect(half == ["DialogueHappy": 0.5])
        let gone = FacialExpressionCore.ease(half, toward: [:], step: 1)
        #expect(gone.isEmpty)
    }

    @Test func theFaceSettingsComeFromTheGame() throws {
        let store = try GameSettingFixture.store([
            "fBlinkDelayMax": .float(4), "fEyePitchMaxOffsetEmotionSad": .float(0.2),
            "fGameplaySpeakingEmotionMaxChangeValue": .float(3)
        ])
        let settings = FaceAnimationSettings.resolve(store: store)
        #expect(settings.blinkDelayMax == 4 && settings.blinkDelayMin == 0.5)
        #expect(settings.eyeRanges["Sad"]?.pitchMax == 0.2)
        #expect(settings.speakingChangeMax == 3)
    }

    @Test func aBlinkIsAddedOnTopOfAnEmotion() {
        let weights = FacialExpressionCore.weights(
            emotion: ["DialogueSad": 0.4], eyes: ["LookUp": 0.2], blink: 1
        )
        #expect(weights == ["DialogueSad": 0.4, "LookUp": 0.2, "BlinkLeft": 1, "BlinkRight": 1])
    }

    @Test func aTimedEmotionEndsOnItsOwn() {
        final class World: FaceMorphWorld {
            var faceMorphSubject: FormID?
            let playback = FaceMorphPlayback(
                actor: FormID(0x10), bindings: [:], pairedPaths: [], misses: []
            )
            func faceMorphPlayback(for _: FormID) -> FaceMorphPlayback? {
                playback
            }

            var faceMorphPlaybacks: [FaceMorphPlayback] {
                [playback]
            }
        }
        let world = World()
        let coordinator = FaceMorphCoordinator(world: world)
        coordinator.automaticBlinkingEnabled = false
        coordinator.showEmotion(.fear, value: 100, on: FormID(0x10), now: 0, seconds: 1)
        coordinator.tick(now: 0.5)
        // The playback has no TRI targets, so nothing is uploaded, but nothing breaks.
        #expect(world.playback.expressionWeights.isEmpty)
        coordinator.tick(now: 2)
        #expect(world.playback.expressionWeights.isEmpty)
    }
}
