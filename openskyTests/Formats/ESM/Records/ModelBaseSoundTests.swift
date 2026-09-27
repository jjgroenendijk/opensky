// M9.2.2 sound-field coverage on ModelBase (DOOR/ACTI/CONT). Synthetic ESM
// fields only. Layout: xEdit dev-4.1.6 wbDefinitionsTES5.pas lines 4921-4923
// (DOOR), 3323-3324 (ACTI), 4519-4520 (CONT); see docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

extension RecordDecoderTests {
    @Test func decodesDoorSoundFields() throws {
        let fields = ESMFixture.field("SNAM", formID(0x100))
            + ESMFixture.field("ANAM", formID(0x101))
            + ESMFixture.field("BNAM", formID(0x102))
        let base = try ModelBase(record: record(ESMFixture.record(
            "DOOR", formID: 0x10, data: fields
        )))
        let sounds = try #require(base.sounds)
        #expect(sounds.activation == FormID(0x100))
        #expect(sounds.close == FormID(0x101))
        #expect(sounds.loop == FormID(0x102))
    }

    @Test func decodesActivatorSoundFields() throws {
        let fields = ESMFixture.field("SNAM", formID(0x200))
            + ESMFixture.field("VNAM", formID(0x201))
        let base = try ModelBase(record: record(ESMFixture.record(
            "ACTI", formID: 0x20, data: fields
        )))
        let sounds = try #require(base.sounds)
        // ACTI.SNAM is the looping bed, ACTI.VNAM is the activation one-shot.
        #expect(sounds.loop == FormID(0x200))
        #expect(sounds.activation == FormID(0x201))
        #expect(sounds.close == nil)
    }

    @Test func decodesContainerSoundFields() throws {
        // CONT close is QNAM, not ANAM — the cross-record trap.
        let fields = ESMFixture.field("SNAM", formID(0x300))
            + ESMFixture.field("QNAM", formID(0x301))
        let base = try ModelBase(record: record(ESMFixture.record(
            "CONT", formID: 0x30, data: fields
        )))
        let sounds = try #require(base.sounds)
        #expect(sounds.activation == FormID(0x300))
        #expect(sounds.close == FormID(0x301))
        #expect(sounds.loop == nil)
    }

    @Test func ignoresDoorSoundFieldsOnOtherTypes() throws {
        // ANAM/BNAM on CONT are different (non-sound) authoring fields and
        // must not contribute to ModelBase.sounds.
        let fields = ESMFixture.field("ANAM", formID(0x400))
            + ESMFixture.field("BNAM", formID(0x401))
        let base = try ModelBase(record: record(ESMFixture.record(
            "CONT", formID: 0x40, data: fields
        )))
        #expect(base.sounds == nil)
    }

    @Test func soundsNilWhenAllFieldsAbsent() throws {
        let base = try ModelBase(record: record(ESMFixture.record(
            "DOOR", data: ESMFixture.field("EDID", ESMFixture.zstring("Quiet"))
        )))
        #expect(base.sounds == nil)
    }

    @Test func skipsMalformedSoundFields() throws {
        // Wrong-size sound fields are skipped rather than throwing — mod-quirk
        // defense (AGENTS.md: malformed input must not crash the engine).
        let fields = ESMFixture.field("SNAM", Data(count: 3))
            + ESMFixture.field("QNAM", Data(count: 5))
        let base = try ModelBase(record: record(ESMFixture.record(
            "CONT", formID: 0x50, data: fields
        )))
        #expect(base.sounds == nil)
    }

    @Test func ignoresNullFormIDsInSoundFields() throws {
        let fields = ESMFixture.field("SNAM", formID(0))
        let base = try ModelBase(record: record(ESMFixture.record(
            "DOOR", formID: 0x60, data: fields
        )))
        #expect(base.sounds == nil)
    }

    private func formID(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
