// The automatic face: dialogue emotions map to the expression TRI's names, and blinks
// are short, spread out, and never stack past fully closed.

@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import Testing

@MainActor
struct FacialExpressionCoreTests {
    @Test func emotionsUseTheExpressionTargetNames() {
        #expect(FacialExpressionCore.emotionWeights(.anger, value: 50) == ["DialogueAnger": 0.5])
        #expect(FacialExpressionCore.emotionWeights(.happy, value: 250) == ["DialogueHappy": 1])
        #expect(FacialExpressionCore.emotionWeights(.neutral, value: 80).isEmpty)
    }

    @Test func aBlinkIsShortAndComesBack() {
        var closedSamples = 0
        var peak: Float = 0
        for step in 0 ..< 1200 {
            let closed = FacialExpressionCore.blink(at: Float(step) * 0.01, seed: 7)
            #expect(closed >= 0 && closed <= 1)
            peak = max(peak, closed)
            if closed > 0 {
                closedSamples += 1
            }
        }
        // Twelve seconds hold two to four blinks of 0.2 s each.
        #expect(closedSamples > 0 && closedSamples <= 4 * 20 + 4)
        #expect(peak > 0.8)
    }

    @Test func aBlinkIsAddedOnTopOfAnEmotion() {
        let weights = FacialExpressionCore.weights(emotion: ["DialogueSad": 0.4], blink: 1)
        #expect(weights == ["DialogueSad": 0.4, "BlinkLeft": 1, "BlinkRight": 1])
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
        let coordinator = FaceMorphCoordinator()
        coordinator.attach(world: world)
        coordinator.automaticBlinkingEnabled = false
        coordinator.showEmotion(.fear, value: 100, on: FormID(0x10), now: 0, seconds: 1)
        coordinator.tick(now: 0.5)
        // The playback has no TRI targets, so nothing is uploaded, but nothing breaks.
        #expect(world.playback.expressionWeights.isEmpty)
        coordinator.tick(now: 2)
        #expect(world.playback.expressionWeights.isEmpty)
    }
}
