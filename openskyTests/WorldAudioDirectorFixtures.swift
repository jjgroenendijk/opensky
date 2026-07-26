// Shared synthetic fixtures for the WorldAudioSoundDirector test suites: an
// offline-rendering engine, a stubbed file loader, and in-code SNDR/SOUN and
// REGN plugins. No real audio device, no VFS, no extracted game file.

import AVFAudio
import Foundation
@testable import opensky
import simd
import Testing

@MainActor
enum WorldAudioDirectorFixture {
    static let sampleRate = 44100.0

    /// Synthetic region shape for the ambience cases.
    struct Region {
        let id: UInt32
        let sounds: [Sound]
    }

    /// Synthetic RDSA entry.
    struct Sound {
        let sound: UInt32
        let flags: UInt32
        let chance: Float
    }

    /// Engine in manual offline-rendering mode, so tests never touch an output
    /// device and never depend on decode-queue timing.
    static func makeRunningEngine() throws -> WorldAudioEngine {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        )
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        engine.isEnabled = true
        try #require(engine.isRunning, "offline engine failed: \(engine.unavailableReason ?? "")")
        return engine
    }

    static func makeDirector(
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

    /// Director wired to one region (`0x100`) whose sound area names sound
    /// `0xAAA`, the shape every ambience case needs.
    static func makeAmbienceDirector(engine: WorldAudioEngine) -> WorldAudioSoundDirector {
        makeDirector(
            engine: engine,
            soundStore: makeSoundStore(
                soundID: 0xAAA, descriptorID: 0xBBB, tracks: ["ambient/cave.xwm"]
            ),
            weatherStore: makeWeatherStore(regions: [
                Region(id: 0x100, sounds: [Sound(sound: 0xAAA, flags: 0, chance: 1)])
            ])
        )
    }

    /// Ambience context naming region `0x100`, the one `makeAmbienceDirector`
    /// knows about.
    static let regionContext = AmbienceContext(
        regions: [FormID(0x100)], acousticSpace: nil, isInterior: false
    )

    static func makeWeatherStore(regions: [Region]) -> WeatherStore {
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

    static func makeSoundStore(
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

    static func makeInteractionEvent(sounds: ModelBase.Sounds?) -> InteractionEvent {
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

    private static func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
