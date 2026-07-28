// WorldAudioSoundDirector coverage over the offline-render engine: interaction
// SFX, the panel force-trigger, and resolve failures. Ambience-bed behavior
// lives in WorldAudioDirectorAmbienceTests. Fixtures come from
// WorldAudioDirectorFixture — synthetic plugins and a stubbed file loader, no
// real audio device and no VFS. See docs/engine/world-sfx.md.

@testable import opensky
import simd
import Testing

@MainActor
struct WorldAudioSoundDirectorTests {
    private typealias Fixture = WorldAudioDirectorFixture

    @Test func handleInteractionPlaysActivationSound() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeDirector(
            engine: engine,
            soundStore: Fixture.makeSoundStore(
                soundID: 0xAAA, descriptorID: 0xBBB, tracks: ["fx/door.xwm"]
            )
        )

        director.handleInteraction(Fixture.makeInteractionEvent(
            sounds: ModelBase.Sounds(activation: FormID(0xAAA), close: nil, loop: nil)
        ))

        #expect(engine.sources.count == 1)
        #expect(engine.sources.first?.category == .effects)
        #expect(engine.sources.first?.loops == false, "a one-shot effect must not loop")
        #expect(director.lastSFXDescription == "sound\\fx\\door.xwm")
        #expect(director.lastSFXError == nil)
    }

    @Test func handleInteractionNoOpWithoutSounds() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeDirector(engine: engine, soundStore: nil)

        director.handleInteraction(Fixture.makeInteractionEvent(sounds: nil))

        #expect(engine.sources.isEmpty)
    }

    @Test func handleInteractionUsesAuthoredDescriptorCategory() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeDirector(
            engine: engine,
            soundStore: Fixture.makeSoundStore(
                soundID: 0xAAA,
                descriptorID: 0xBBB,
                tracks: ["fx/step.xwm"],
                category: .footsteps
            )
        )

        director.handleInteraction(Fixture.makeInteractionEvent(
            sounds: ModelBase.Sounds(activation: FormID(0xAAA), close: nil, loop: nil)
        ))

        #expect(engine.sources.first?.category == .footsteps)
    }

    @Test func handleInteractionNoOpWhenSfxDisabled() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeDirector(
            engine: engine,
            soundStore: Fixture.makeSoundStore(
                soundID: 0xAAA, descriptorID: 0xBBB, tracks: ["fx/door.xwm"]
            )
        )
        director.sfxEnabled = false

        director.handleInteraction(Fixture.makeInteractionEvent(
            sounds: ModelBase.Sounds(activation: FormID(0xAAA), close: nil, loop: nil)
        ))

        #expect(engine.sources.isEmpty)
    }

    @Test func forcePlaySoundTriggersResolvedSFX() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeDirector(
            engine: engine,
            soundStore: Fixture.makeSoundStore(
                soundID: 0xAAA, descriptorID: 0xBBB, tracks: ["fx/boom.xwm"]
            )
        )

        director.forcePlaySound(formID: FormID(0xAAA), position: SIMD3<Float>(0, 100, 0))

        #expect(engine.sources.count == 1)
        #expect(director.lastSFXDescription == "sound\\fx\\boom.xwm")
    }

    @Test func resolveSoundFailureRecordsError() throws {
        let engine = try Fixture.makeRunningEngine()
        let director = Fixture.makeDirector(engine: engine, soundStore: nil)

        director.forcePlaySound(formID: FormID(0xAAA), position: .zero)

        #expect(engine.sources.isEmpty)
        #expect(director.lastSFXError != nil)
    }
}
