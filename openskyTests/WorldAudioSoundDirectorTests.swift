// WorldAudioSoundDirector coverage over the offline-render engine. Synthetic
// SoundRecordStore + stubbed file loader; no real audio device, no VFS. See
// docs/engine/world-sfx.md.

import AVFAudio
import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct WorldAudioSoundDirectorTests {
    private static let sampleRate = 44100.0

    @Test func handleInteractionPlaysActivationSound() throws {
        let engine = try makeRunningEngine()
        let director = makeDirector(
            engine: engine,
            soundStore: makeSoundStore(soundID: 0xAAA, descriptorID: 0xBBB, tracks: ["fx/door.xwm"])
        )

        director.handleInteraction(makeInteractionEvent(
            sounds: ModelBase.Sounds(activation: FormID(0xAAA), close: nil, loop: nil)
        ))

        #expect(engine.sources.count == 1)
        #expect(engine.sources.first?.category == .effects)
        #expect(director.lastSFXDescription == "sound\\fx\\door.xwm")
        #expect(director.lastSFXError == nil)
    }

    @Test func handleInteractionNoOpWithoutSounds() throws {
        let engine = try makeRunningEngine()
        let director = makeDirector(engine: engine, soundStore: nil)

        director.handleInteraction(makeInteractionEvent(sounds: nil))

        #expect(engine.sources.isEmpty)
    }

    @Test func handleInteractionNoOpWhenSfxDisabled() throws {
        let engine = try makeRunningEngine()
        let director = makeDirector(
            engine: engine,
            soundStore: makeSoundStore(soundID: 0xAAA, descriptorID: 0xBBB, tracks: ["fx/door.xwm"])
        )
        director.sfxEnabled = false

        director.handleInteraction(makeInteractionEvent(
            sounds: ModelBase.Sounds(activation: FormID(0xAAA), close: nil, loop: nil)
        ))

        #expect(engine.sources.isEmpty)
    }

    @Test func handleAmbienceStartsLoopsForNonEmptyBed() throws {
        let engine = try makeRunningEngine()
        let weather = makeWeatherStore(regions: [
            RegionFixture(id: 0x100, sounds: [SoundFixture(sound: 0xAAA, flags: 0, chance: 1)])
        ])
        let director = makeDirector(
            engine: engine,
            soundStore: makeSoundStore(
                soundID: 0xAAA,
                descriptorID: 0xBBB,
                tracks: ["ambient/cave.xwm"]
            ),
            weatherStore: weather
        )

        director.handleAmbienceContext(AmbienceContext(
            regions: [FormID(0x100)],
            acousticSpace: nil,
            isInterior: false
        ))

        #expect(engine.sources.count == 1)
        #expect(engine.sources.first?.category == .ambience)
    }

    @Test func handleAmbienceRetiresPreviousBedOnContextChange() throws {
        let engine = try makeRunningEngine()
        let weather = makeWeatherStore(regions: [
            RegionFixture(id: 0x100, sounds: [SoundFixture(sound: 0xAAA, flags: 0, chance: 1)])
        ])
        let director = makeDirector(
            engine: engine,
            soundStore: makeSoundStore(
                soundID: 0xAAA,
                descriptorID: 0xBBB,
                tracks: ["ambient/cave.xwm"]
            ),
            weatherStore: weather
        )

        director.handleAmbienceContext(AmbienceContext(
            regions: [FormID(0x100)], acousticSpace: nil, isInterior: false
        ))
        #expect(engine.sources.count == 1)

        // Same context: no-op (cached bed).
        director.handleAmbienceContext(AmbienceContext(
            regions: [FormID(0x100)], acousticSpace: nil, isInterior: false
        ))
        #expect(engine.sources.count == 1)

        // Empty context: retires the previous bed.
        director.handleAmbienceContext(AmbienceContext.empty)
        #expect(engine.sources.isEmpty)
    }

    @Test func handleAmbienceNoOpWhenDisabled() throws {
        let engine = try makeRunningEngine()
        let weather = makeWeatherStore(regions: [
            RegionFixture(id: 0x100, sounds: [SoundFixture(sound: 0xAAA, flags: 0, chance: 1)])
        ])
        let director = makeDirector(
            engine: engine,
            soundStore: makeSoundStore(
                soundID: 0xAAA,
                descriptorID: 0xBBB,
                tracks: ["ambient/cave.xwm"]
            ),
            weatherStore: weather
        )
        director.ambienceEnabled = false

        director.handleAmbienceContext(AmbienceContext(
            regions: [FormID(0x100)], acousticSpace: nil, isInterior: false
        ))

        #expect(engine.sources.isEmpty)
    }

    @Test func forcePlaySoundTriggersResolvedSFX() throws {
        let engine = try makeRunningEngine()
        let director = makeDirector(
            engine: engine,
            soundStore: makeSoundStore(soundID: 0xAAA, descriptorID: 0xBBB, tracks: ["fx/boom.xwm"])
        )

        director.forcePlaySound(formID: FormID(0xAAA), position: SIMD3<Float>(0, 100, 0))

        #expect(engine.sources.count == 1)
        #expect(director.lastSFXDescription == "sound\\fx\\boom.xwm")
    }

    @Test func resolveSoundFailureRecordsError() throws {
        let engine = try makeRunningEngine()
        let director = makeDirector(engine: engine, soundStore: nil)

        director.forcePlaySound(formID: FormID(0xAAA), position: .zero)

        #expect(engine.sources.isEmpty)
        #expect(director.lastSFXError != nil)
    }

    // MARK: - Helpers

    private func makeRunningEngine() throws -> WorldAudioEngine {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2)
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        engine.isEnabled = true
        try #require(engine.isRunning, "offline engine failed: \(engine.unavailableReason ?? "")")
        return engine
    }

    private func makeDirector(
        engine: WorldAudioEngine,
        soundStore: SoundRecordStore?,
        weatherStore: WeatherStore? = nil
    ) -> WorldAudioSoundDirector {
        WorldAudioSoundDirector(
            engine: engine,
            soundStore: soundStore,
            weatherStore: weatherStore,
            aspcStore: nil,
            fileLoader: { _ in XWMFixture.file() }
        )
    }

    private func makeWeatherStore(
        regions: [RegionFixture]
    ) -> WeatherStore {
        var bytes = Data()
        for region in regions {
            var soundHeader = Data()
            soundHeader.appendUInt32(7) // type: sound
            soundHeader.append(contentsOf: [0x00, 1])
            soundHeader.appendUInt16(0)
            var rdsa = Data()
            for entry in region.sounds {
                rdsa.appendUInt32(entry.sound)
                rdsa.appendUInt32(entry.flags)
                rdsa.appendUInt32(entry.chance.bitPattern)
            }
            var fields = ESMFixture.field("EDID", ESMFixture.zstring("Region\(region.id)"))
            fields += ESMFixture.field("RDAT", soundHeader)
            if !rdsa.isEmpty {
                fields += ESMFixture.field("RDSA", rdsa)
            }
            bytes += ESMFixture.record("REGN", formID: region.id, data: fields)
        }
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup("REGN", contents: bytes)
        do {
            return try WeatherStore(file: ESMFile(data: plugin))
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }

    private func makeSoundStore(
        soundID: UInt32,
        descriptorID: UInt32,
        tracks: [String]
    ) -> SoundRecordStore {
        var descriptorFields = Data()
        for track in tracks {
            descriptorFields += ESMFixture.field("ANAM", ESMFixture.zstring(track))
        }
        let soundFields = ESMFixture.field("SDSC", uint32(descriptorID))
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup("SNDR", contents: ESMFixture.record(
                "SNDR", formID: descriptorID, data: descriptorFields
            ))
            + ESMFixture.topGroup("SOUN", contents: ESMFixture.record(
                "SOUN", formID: soundID, data: soundFields
            ))
        do {
            return try SoundRecordStore(file: ESMFile(data: plugin))
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }

    /// Synthetic region-fixture shape for the ambience tests.
    struct RegionFixture {
        let id: UInt32
        let sounds: [SoundFixture]
    }

    /// Synthetic RDSA entry.
    struct SoundFixture {
        let sound: UInt32
        let flags: UInt32
        let chance: Float
    }

    private func makeInteractionEvent(sounds: ModelBase.Sounds?) -> InteractionEvent {
        InteractionEvent(target: InteractionTarget(
            interaction: PlacedInteraction(
                reference: FormID(1),
                base: FormID(2),
                position: SIMD3<Float>(10, 0, 0),
                name: "Test",
                action: .open,
                actionLabel: "Open",
                sounds: sounds
            ),
            hitPosition: SIMD3<Float>(10, 0, 0),
            distance: 5
        ))
    }

    private func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
