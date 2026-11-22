// The sound event rule: how far an event reaches, its sound-only value, and what the
// runtime does with it. docs/engine/detection-events.md.

import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyPerception
@testable import OpenSkyPerceptionInterface
import OpenSkyPhysics
import simd
import Testing

@MainActor
struct DetectionEventRuleTests {
    private let settings = DetectionSettings.synthetic

    private func advance(_ runtime: PerceptionRuntime, steps: Int) {
        for _ in 0 ..< steps {
            runtime.advance(by: PerceptionRuntime.fixedStepSeconds)
        }
    }

    private func world(observerAt feet: SIMD3<Float> = .zero) -> FakePerceptionWorld {
        var observer = PerceptionFixture.observer(feet: feet, facing: .pi)
        observer.isAggressive = true
        return FakePerceptionWorld(
            observers: [observer],
            targets: [PerceptionFixture.target(
                feet: SIMD3(3000, 0, 0), gait: nil, isSneaking: true
            )]
        )
    }

    @Test func thePlayersSoundReachesFartherAndAVeryLoudOneTwiceAsFar() {
        #expect(DetectionEventRule.hearingDistance(level: 50, isPlayerSound: true) == 1536)
        #expect(DetectionEventRule.hearingDistance(level: 50, isPlayerSound: false) == 512)
        #expect(DetectionEventRule.hearingDistance(level: 200, isPlayerSound: true) == 3072)
        #expect(DetectionEventRule.hearingDistance(level: 200, isPlayerSound: false) == 1024)
    }

    @Test func aLouderNearerOrSeenEventGivesAHigherValue() {
        let inputs = DetectionInputs(distance: 0, isExterior: false, gait: nil)
        func value(_ level: Float, _ distance: Float, seen: Bool = false) -> Float {
            DetectionEventRule.value(
                of: DetectionSoundEvent(level: level, position: .zero),
                sight: DetectionEventSight(
                    distance: distance, hasLineOfSight: seen, isInViewCone: seen
                ),
                inputs: inputs, settings: settings
            )
        }
        #expect(value(100, 100) > value(10, 100))
        #expect(value(100, 100) > value(100, 900))
        #expect(value(50, 100, seen: true) > value(50, 100))
        // Past the range the formula does not run. A very loud event has its own range.
        let range = DetectionFormula.maximumDistance(settings: settings, isExterior: false)
        #expect(value(100, range + 1) == settings.sneakBaseValue.value)
        #expect(value(200, 3072) == settings.sneakBaseValue.value)
        #expect(value(200, .nan) == settings.sneakBaseValue.value)
        var asleep = inputs
        asleep.observer.isSleeping = true
        #expect(
            DetectionEventRule.value(
                of: DetectionSoundEvent(level: 50, position: .zero),
                sight: DetectionEventSight(
                    distance: 100, hasLineOfSight: true, isInViewCone: true
                ),
                inputs: asleep, settings: settings
            ) < value(50, 100, seen: true)
        )
    }

    @Test func anEventOutOfHearingDistanceIsNotChecked() {
        let world = world()
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 1)
        runtime.noteSoundEvent(owner: .player, level: 50, at: SIMD3(1600, 0, 0))
        advance(runtime, steps: 2)
        let pair = runtime.state(observer: PerceptionFixture.guardKey, target: .player)
        #expect(pair.state == .unaware)
        // A very loud sound at the same place is heard.
        runtime.noteSoundEvent(owner: .player, level: 200, at: SIMD3(1600, 0, 0))
        advance(runtime, steps: 2)
        #expect(
            runtime.state(observer: PerceptionFixture.guardKey, target: .player).state
                == .suspicious
        )
    }

    @Test func anEventLastsFiveSecondsAndANewOneReplacesIt() {
        let world = world()
        let runtime = PerceptionRuntime(settings: settings, world: world)
        runtime.noteSoundEvent(owner: .player, level: 50, at: SIMD3(1, 0, 0))
        runtime.noteSoundEvent(owner: .player, level: 100, at: SIMD3(2, 0, 0))
        runtime.noteSoundEvent(owner: .player, level: -1, at: SIMD3(3, 0, 0))
        #expect(runtime.soundEvent(of: .player)?.level == 100)
        runtime.noteSummon(by: PerceptionFixture.guardKey, at: .zero)
        #expect(runtime.soundEvent(of: PerceptionFixture.guardKey)?.level == 100)
        advance(runtime, steps: 60 * 4)
        #expect(runtime.soundEvent(of: .player) != nil)
        advance(runtime, steps: 61)
        #expect(runtime.soundEvent(of: .player) == nil)
    }

    @Test func aCastKeepsItsCastersEventNewAndIsHeardOnce() {
        let world = world()
        var traits = DetectionTargetTraits()
        traits.castingSound = 50
        world.targets = [PerceptionTarget(
            key: .player, feet: SIMD3(400, 0, 0), gait: nil, isSneaking: true, traits: traits,
            name: "Player"
        )]
        world.blocked = PerceptionFixture.wall(atX: 200)
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 120)
        let event = runtime.soundEvent(of: .player)
        #expect(event?.position == SIMD3(400, 0, 0))
        #expect((event?.age ?? 1) < 0.1)
        let pair = runtime.state(observer: PerceptionFixture.guardKey, target: .player)
        #expect(pair.lastKnownPosition == SIMD3(400, 0, 0))
        #expect(runtime.targetTrack(of: .player).lastKnown == SIMD3(400, 0, 0))
    }
}
