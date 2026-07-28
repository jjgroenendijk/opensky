// SNCT decoding and SNDR.GNAM -> SNCT.PNAM category resolution over synthetic
// ESM fields only. Layout sources: UESP SNCT and xEdit
// wbDefinitionsTES5.pas; see docs/formats/sound.md.

import Foundation
@testable import opensky
import Testing

struct SoundCategoryRecordTests {
    @Test func decodesCompleteSoundCategory() throws {
        var staticVolume = Data()
        staticVolume.appendUInt16(UInt16.max)
        var menuValue = Data()
        menuValue.appendUInt16(32767)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("AudioCategorySFX"))
            + ESMFixture.field("FULL", ESMFixture.zstring("Effects"))
            + ESMFixture.field("FNAM", uint32(3))
            + ESMFixture.field("PNAM", uint32(0x100))
            + ESMFixture.field("VNAM", staticVolume)
            + ESMFixture.field("UNAM", menuValue)
        let category = try SoundCategory(
            record: record(ESMFixture.record("SNCT", formID: 0x200, data: fields)),
            localized: false
        )

        #expect(category.formID == FormID(0x200))
        #expect(category.editorID == "AudioCategorySFX")
        #expect(category.name == .inline("Effects"))
        #expect(category.flags == [.muteWhenSubmerged, .shouldAppearOnMenu])
        #expect(category.parent == FormID(0x100))
        #expect(category.staticVolumeMultiplier == 1)
        let defaultMenuValue = try #require(category.defaultMenuValue)
        #expect(abs(defaultMenuValue - Float(32767) / Float(UInt16.max)) < 0.0001)
    }

    @Test func skipsWrongSizeOptionalStructures() throws {
        let fields = ESMFixture.field("FNAM", Data(count: 3))
            + ESMFixture.field("PNAM", Data(count: 3))
            + ESMFixture.field("VNAM", Data(count: 1))
            + ESMFixture.field("UNAM", Data(count: 3))
        let category = try SoundCategory(
            record: record(ESMFixture.record("SNCT", data: fields)),
            localized: false
        )

        #expect(category.flags.isEmpty)
        #expect(category.parent == nil)
        #expect(category.staticVolumeMultiplier == nil)
        #expect(category.defaultMenuValue == nil)
    }

    @Test func wrongRecordTypeThrows() throws {
        #expect(throws: ESMError.self) {
            _ = try SoundCategory(
                record: record(ESMFixture.record("SNDR", data: Data())),
                localized: false
            )
        }
    }

    @Test func storeResolvesDescriptorCategoryThroughSNCTParents() throws {
        let menuCategory = ESMFixture.field(
            "EDID", ESMFixture.zstring("AudioCategorySFX")
        ) + ESMFixture.field("FNAM", uint32(2))
        let childCategory = ESMFixture.field(
            "EDID", ESMFixture.zstring("AudioCategoryAMB")
        ) + ESMFixture.field("PNAM", uint32(0x100))
        let descriptor = ESMFixture.field("GNAM", uint32(0x101))
            + ESMFixture.field("ANAM", ESMFixture.zstring("ambient\\wind.xwm"))
        let store = try soundStore(
            descriptor: descriptor,
            categories: ESMFixture.record("SNCT", formID: 0x100, data: menuCategory)
                + ESMFixture.record("SNCT", formID: 0x101, data: childCategory)
        )

        let resolved = try store.resolveAny(FormID(0x200))
        #expect(resolved.audioCategory == .effects)
        #expect(store.category(FormID(0x101))?.parent == FormID(0x100))
    }

    @Test func malformedCategoryCycleTerminatesWithoutMapping() throws {
        let first = ESMFixture.field("EDID", ESMFixture.zstring("CycleA"))
            + ESMFixture.field("PNAM", uint32(0x101))
        let second = ESMFixture.field("EDID", ESMFixture.zstring("CycleB"))
            + ESMFixture.field("PNAM", uint32(0x100))
        let store = try soundStore(
            descriptor: ESMFixture.field("GNAM", uint32(0x100)),
            categories: ESMFixture.record("SNCT", formID: 0x100, data: first)
                + ESMFixture.record("SNCT", formID: 0x101, data: second)
        )

        #expect(try store.resolveAny(FormID(0x200)).audioCategory == nil)
    }

    @Test func audioCategoryMatchesVanillaMenuTaxonomy() {
        #expect(AudioCategory.allCases == [.effects, .voice, .music, .footsteps])
        #expect(AudioCategory.effects.soundCategoryEditorID == "AudioCategorySFX")
        #expect(AudioCategory.voice.soundCategoryEditorID == "AudioCategoryVOCGeneral")
        #expect(AudioCategory.music.soundCategoryEditorID == "AudioCategoryMUS")
        #expect(AudioCategory.footsteps.soundCategoryEditorID == "AudioCategoryFST")
        #expect(AudioCategory(soundCategoryEditorID: "audiocategorysfx") == .effects)
        #expect(AudioCategory(soundCategoryEditorID: "unknown") == nil)
    }

    private func soundStore(
        descriptor: Data,
        categories: Data
    ) throws -> SoundRecordStore {
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup(
                "SNDR",
                contents: ESMFixture.record("SNDR", formID: 0x200, data: descriptor)
            )
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
