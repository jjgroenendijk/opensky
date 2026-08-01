// SNDR/SOUN decoding and resolution coverage over synthetic ESM fields only.
// Layout sources: UESP SNDR/SOUN and xEdit wbDefinitionsTES5.pas; see
// docs/formats/sound.md.

import Foundation
@testable import opensky
import Testing

struct SoundRecordTests {
    @Test func decodesCompleteDescriptor() throws {
        var parameters = Data([
            UInt8(bitPattern: Int8(-12)),
            UInt8(bitPattern: Int8(7)),
            80,
            6
        ])
        parameters.appendUInt16(1234)

        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestDescriptor"))
            + ESMFixture.field("CNAM", uint32(3))
            + ESMFixture.field("GNAM", uint32(0x100))
            + ESMFixture.field("SNAM", uint32(0x101))
            + ESMFixture.field("ANAM", ESMFixture.zstring("FX\\First.wav"))
            + ESMFixture.field("ANAM", ESMFixture.zstring("FX\\Second.xwm"))
            + ESMFixture.field("ONAM", uint32(0x102))
            + ESMFixture.field("LNAM", Data([4, 8, 5, 6]))
            + ESMFixture.field("BNAM", parameters)
        let descriptor = try SoundDescriptor(record: record(
            ESMFixture.record("SNDR", formID: 0x200, data: fields)
        ))

        #expect(descriptor.formID == FormID(0x200))
        #expect(descriptor.editorID == "TestDescriptor")
        #expect(descriptor.descriptorType == 3)
        #expect(descriptor.category == FormID(0x100))
        #expect(descriptor.alternateFor == FormID(0x101))
        #expect(descriptor.tracks == ["FX\\First.wav", "FX\\Second.xwm"])
        #expect(descriptor.outputModel == FormID(0x102))
        #expect(descriptor.looping == .loop)
        let decoded = try #require(descriptor.parameters)
        #expect(decoded.frequencyShiftPercent == -12)
        #expect(decoded.frequencyVariancePercent == 7)
        #expect(decoded.priority == 80)
        #expect(decoded.decibelVariance == 6)
        #expect(abs(decoded.staticAttenuationDecibels - 12.34) < 0.0001)
    }

    @Test func decodesSoundMarkerDescriptorLink() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestSound"))
            + ESMFixture.field("SDSC", uint32(0x200))
            + ESMFixture.field("FNAM", Data([1]))
            + ESMFixture.field("SNDD", Data([2, 3]))
        let sound = try SoundMarker(record: record(
            ESMFixture.record("SOUN", formID: 0x300, data: fields)
        ))

        #expect(sound.formID == FormID(0x300))
        #expect(sound.editorID == "TestSound")
        #expect(sound.descriptor == FormID(0x200))
    }

    @Test func decodesEveryLoopingSelector() throws {
        let cases: [(UInt8, SoundDescriptor.Looping)] = [
            (0, .none),
            (8, .loop),
            (16, .envelopeFast),
            (32, .envelopeSlow),
            (0x7F, .unknown(0x7F))
        ]

        for (selector, expected) in cases {
            let fields = ESMFixture.field("LNAM", Data([1, selector, 2, 3]))
            let descriptor = try SoundDescriptor(record: record(
                ESMFixture.record("SNDR", data: fields)
            ))
            #expect(descriptor.looping == expected)
        }
    }

    @Test func skipsWrongSizeOptionalStructures() throws {
        let descriptorFields = ESMFixture.field("CNAM", Data(count: 3))
            + ESMFixture.field("GNAM", Data(count: 3))
            + ESMFixture.field("SNAM", Data(count: 5))
            + ESMFixture.field("ONAM", Data(count: 2))
            + ESMFixture.field("LNAM", Data(count: 3))
            + ESMFixture.field("BNAM", Data(count: 5))
        let descriptor = try SoundDescriptor(record: record(
            ESMFixture.record("SNDR", data: descriptorFields)
        ))
        #expect(descriptor.descriptorType == nil)
        #expect(descriptor.category == nil)
        #expect(descriptor.alternateFor == nil)
        #expect(descriptor.outputModel == nil)
        #expect(descriptor.looping == nil)
        #expect(descriptor.parameters == nil)

        let markerFields = ESMFixture.field("SDSC", Data(count: 3))
        let marker = try SoundMarker(record: record(
            ESMFixture.record("SOUN", data: markerFields)
        ))
        #expect(marker.descriptor == nil)
    }

    @Test func wrongRecordTypesThrow() throws {
        #expect(throws: ESMError.self) {
            _ = try SoundDescriptor(record: record(
                ESMFixture.record("SOUN", data: Data())
            ))
        }
        #expect(throws: ESMError.self) {
            _ = try SoundMarker(record: record(
                ESMFixture.record("SNDR", data: Data())
            ))
        }
    }

    @Test func storeResolvesDirectRecordsAndCanonicalPathsInOrder() throws {
        let descriptorFields = ESMFixture.field(
            "ANAM",
            ESMFixture.zstring("FX/Thunder.WAV")
        ) + ESMFixture.field(
            "ANAM",
            ESMFixture.zstring("sound\\Ambient\\Rain.xwm")
        ) + ESMFixture.field(
            "ANAM",
            ESMFixture.zstring("UI//Click.wav")
        ) + ESMFixture.field(
            "ANAM",
            ESMFixture.zstring("Data\\Sound\\FX\\Wrapped.wav")
        ) + ESMFixture.field(
            "ANAM",
            ESMFixture.zstring("FX/../Unsafe.wav")
        ) + ESMFixture.field(
            "ANAM",
            ESMFixture.zstring("C:\\Build\\Absolute.wav")
        ) + ESMFixture.field(
            "ANAM",
            ESMFixture.zstring("/Sound/UI/ForwardRoot.wav")
        )
        let soundFields = ESMFixture.field("SDSC", uint32(0x200))
        let store = try soundStore(
            descriptors: ESMFixture.record("SNDR", formID: 0x200, data: descriptorFields),
            sounds: ESMFixture.record("SOUN", formID: 0x300, data: soundFields)
        )

        #expect(store.descriptor(FormID(0x200))?.formID == FormID(0x200))
        #expect(store.sound(FormID(0x300))?.formID == FormID(0x300))
        let resolved = try store.resolve(sound: FormID(0x300))
        #expect(resolved.sound.formID == FormID(0x300))
        #expect(resolved.descriptor.formID == FormID(0x200))
        #expect(resolved.audioCategory == nil)
        #expect(resolved.filePaths == [
            "sound\\fx\\thunder.wav",
            "sound\\ambient\\rain.xwm",
            "sound\\ui\\click.wav",
            "sound\\fx\\wrapped.wav",
            "sound\\ui\\forwardroot.wav"
        ])
    }

    /// Vanilla SNDR records use this Windows root-relative authoring form. The
    /// leading separator is not a drive or volume and must not drop the track.
    @Test func separatorLedDataRootedTrackSurvivesCanonicalization() throws {
        let track = "\\Data\\Sound\\FX\\SeparatorLed.wav"
        let descriptor = ESMFixture.field("ANAM", ESMFixture.zstring(track))
        let store = try soundStore(
            descriptors: ESMFixture.record("SNDR", formID: 0x200, data: descriptor),
            sounds: Data()
        )

        let resolved = try store.resolveAny(FormID(0x200))
        #expect(resolved.filePaths == ["sound\\fx\\separatorled.wav"])
    }

    @Test func missingSoundThrowsTypedError() throws {
        let store = try soundStore(descriptors: Data(), sounds: Data())
        #expect(throws: SoundResolveError.soundNotFound(FormID(0x300))) {
            _ = try store.resolve(sound: FormID(0x300))
        }
    }

    @Test func missingDescriptorThrowsTypedErrors() throws {
        let linked = ESMFixture.field("SDSC", uint32(0x200))
        let linkedStore = try soundStore(
            descriptors: Data(),
            sounds: ESMFixture.record("SOUN", formID: 0x300, data: linked)
        )
        #expect(throws: SoundResolveError.descriptorNotFound(
            FormID(0x200),
            sound: FormID(0x300)
        )) {
            _ = try linkedStore.resolve(sound: FormID(0x300))
        }

        let unlinkedStore = try soundStore(
            descriptors: Data(),
            sounds: ESMFixture.record("SOUN", formID: 0x301, data: Data())
        )
        #expect(throws: SoundResolveError.descriptorNotFound(
            FormID(0),
            sound: FormID(0x301)
        )) {
            _ = try unlinkedStore.resolve(sound: FormID(0x301))
        }
    }

    private func soundStore(
        descriptors: Data,
        sounds: Data,
        categories: Data = Data()
    ) throws -> SoundRecordStore {
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup("SNDR", contents: descriptors)
            + ESMFixture.topGroup("SOUN", contents: sounds)
            + ESMFixture.topGroup("SNCT", contents: categories)
        return try SoundRecordStore(file: ESMFile(data: plugin))
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    private func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
