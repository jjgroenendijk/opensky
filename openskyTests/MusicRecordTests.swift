// MUSC/MUST decoder coverage over synthetic ESM field bytes only.
// Layouts: UESP "Skyrim Mod:Mod File Format/MUSC" and ".../MUST", xEdit
// dev-4.1.6 wbDefinitionsTES5.pas lines 7074-7092 and 7203-7226.
// See docs/formats/music.md.

import Foundation
@testable import opensky
import Testing

struct MusicRecordTests {
    // MARK: - MUSC

    @Test func decodesCompleteMusicType() throws {
        var pnam = Data()
        pnam.appendUInt16(7) // priority
        pnam.appendUInt16(126) // ducking, scaled by 100
        var wnam = Data()
        wnam.appendFloat32(2.5)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("MUSExplore"))
            + ESMFixture.field("FNAM", uint32(0x0004 | 0x0008 | 0x0020))
            + ESMFixture.field("PNAM", pnam)
            + ESMFixture.field("WNAM", wnam)
            + ESMFixture.field("TNAM", uint32(0x100) + uint32(0x101) + uint32(0x102))
        let musc = try MusicType(record: record(ESMFixture.record(
            "MUSC", formID: 0x20, data: fields
        )))

        #expect(musc.formID == FormID(0x20))
        #expect(musc.editorID == "MUSExplore")
        #expect(musc.flags.contains(.cycleTracks))
        #expect(musc.flags.contains(.maintainTrackOrder))
        #expect(musc.flags.contains(.ducksCurrentTrack))
        #expect(!musc.flags.contains(.playsOneSelection))
        #expect(musc.priority == 7)
        #expect(musc.duckingDecibels == 1.26)
        #expect(musc.fadeDuration == 2.5)
        #expect(musc.tracks == [FormID(0x100), FormID(0x101), FormID(0x102)])
    }

    @Test func decodesBareMusicType() throws {
        let musc = try MusicType(record: record(ESMFixture.record(
            "MUSC", data: ESMFixture.field("EDID", ESMFixture.zstring("Bare"))
        )))
        #expect(musc.flags.isEmpty)
        #expect(musc.priority == nil)
        #expect(musc.duckingDecibels == nil)
        #expect(musc.fadeDuration == nil)
        #expect(musc.tracks.isEmpty)
    }

    @Test func skipsWrongWidthMusicTypeFields() throws {
        let fields = ESMFixture.field("FNAM", Data(count: 2))
            + ESMFixture.field("PNAM", Data(count: 3))
            + ESMFixture.field("WNAM", Data(count: 5))
            + ESMFixture.field("TNAM", Data(count: 6))
        let musc = try MusicType(record: record(ESMFixture.record(
            "MUSC", formID: 0x21, data: fields
        )))
        #expect(musc.flags.isEmpty)
        #expect(musc.priority == nil)
        #expect(musc.fadeDuration == nil)
        #expect(musc.tracks.isEmpty)
    }

    @Test func keepsNullTrackLinksInRecordOrder() throws {
        let fields = ESMFixture.field("TNAM", uint32(0x100) + uint32(0) + uint32(0x102))
        let musc = try MusicType(record: record(ESMFixture.record(
            "MUSC", formID: 0x22, data: fields
        )))
        #expect(musc.tracks == [FormID(0x100), FormID(0), FormID(0x102)])
    }

    @Test func wrongMusicTypeRecordTypeThrows() throws {
        #expect(throws: ESMError.self) {
            _ = try MusicType(record: record(ESMFixture.record("MUST", data: Data())))
        }
    }

    // MARK: - MUST

    @Test func decodesSingleTrack() throws {
        var lnam = Data()
        lnam.appendFloat32(1.5)
        lnam.appendFloat32(9.25)
        lnam.appendUInt32(3)
        var fnam = Data()
        fnam.appendFloat32(0.5)
        fnam.appendFloat32(4)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("MUSTExplore01"))
            + ESMFixture.field("CNAM", uint32(0x6ED7_E048))
            + ESMFixture.field("ANAM", ESMFixture.zstring("Music\\Explore\\mus_explore_01.xwm"))
            + ESMFixture.field("BNAM", ESMFixture.zstring("Music\\Explore\\mus_finale.xwm"))
            + ESMFixture.field("LNAM", lnam)
            + ESMFixture.field("FNAM", fnam)
        let must = try MusicTrack(record: record(ESMFixture.record(
            "MUST", formID: 0x100, data: fields
        )))

        #expect(must.formID == FormID(0x100))
        #expect(must.editorID == "MUSTExplore01")
        #expect(must.trackType == .singleTrack)
        #expect(must.trackFileName == "Music\\Explore\\mus_explore_01.xwm")
        #expect(must.finaleFileName == "Music\\Explore\\mus_finale.xwm")
        #expect(must.loopData == MusicTrack.LoopData(
            beginSeconds: 1.5, endSeconds: 9.25, count: 3
        ))
        #expect(must.cuePoints == [0.5, 4])
        #expect(must.duration == nil)
        #expect(must.tracks.isEmpty)
    }

    @Test func decodesSilentTrack() throws {
        var fltv = Data()
        fltv.appendFloat32(12)
        let fields = ESMFixture.field("CNAM", uint32(0xA1A9_C4D5))
            + ESMFixture.field("FLTV", fltv)
        let must = try MusicTrack(record: record(ESMFixture.record(
            "MUST", formID: 0x101, data: fields
        )))
        #expect(must.trackType == .silentTrack)
        #expect(must.duration == 12)
        #expect(must.trackFileName == nil)
    }

    @Test func decodesPaletteTrack() throws {
        var dnam = Data()
        dnam.appendFloat32(3)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("MUSTPalette"))
            + ESMFixture.field("CNAM", uint32(0x23F6_78C3))
            + ESMFixture.field("DNAM", dnam)
            + ESMFixture.field("SNAM", uint32(0x100) + uint32(0) + uint32(0x101))
        let must = try MusicTrack(record: record(ESMFixture.record(
            "MUST", formID: 0x102, data: fields
        )))
        #expect(must.trackType == .palette)
        #expect(must.fadeOut == 3)
        // A null SNAM entry is a layer separator and stays in place.
        #expect(must.tracks == [FormID(0x100), FormID(0), FormID(0x101)])
    }

    @Test func unknownTrackTypeRoundTrips() throws {
        let must = try MusicTrack(record: record(ESMFixture.record(
            "MUST", formID: 0x103, data: ESMFixture.field("CNAM", uint32(0xDEAD_BEEF))
        )))
        #expect(must.trackType == .unknown(0xDEAD_BEEF))
    }

    @Test func skipsWrongWidthMusicTrackFields() throws {
        let fields = ESMFixture.field("CNAM", Data(count: 2))
            + ESMFixture.field("FLTV", Data(count: 3))
            + ESMFixture.field("DNAM", Data(count: 8))
            + ESMFixture.field("LNAM", Data(count: 11))
            + ESMFixture.field("FNAM", Data(count: 6))
            + ESMFixture.field("SNAM", Data(count: 7))
        let must = try MusicTrack(record: record(ESMFixture.record(
            "MUST", formID: 0x104, data: fields
        )))
        #expect(must.trackType == nil)
        #expect(must.duration == nil)
        #expect(must.fadeOut == nil)
        #expect(must.loopData == nil)
        #expect(must.cuePoints.isEmpty)
        #expect(must.tracks.isEmpty)
    }

    @Test func decodesConditionFields() throws {
        // CITC/CTDA route to the shared condition decoder without disturbing
        // the fields around them (docs/formats/conditions.md).
        var ctda = Data([0x01, 0, 0, 0]) // equal, OR with the next condition
        ctda.appendFloat32(1)
        ctda.appendUInt16(576) // function index, raw on-disk value
        ctda.appendUInt16(0)
        ctda.appendUInt32(0x0001_0800) // parameter #1
        ctda.appendUInt32(0)
        ctda.appendUInt32(1) // run on Target
        ctda.appendUInt32(0)
        ctda.appendUInt32(UInt32(bitPattern: -1))
        let fields = ESMFixture.field("CNAM", uint32(0x6ED7_E048))
            + ESMFixture.field("CITC", uint32(1))
            + ESMFixture.field("CTDA", ctda)
            + ESMFixture.field("ANAM", ESMFixture.zstring("Music\\mus.xwm"))
        let must = try MusicTrack(record: record(ESMFixture.record(
            "MUST", formID: 0x105, data: fields
        )))
        #expect(must.trackType == .singleTrack)
        #expect(must.trackFileName == "Music\\mus.xwm")
        #expect(must.declaredConditionCount == 1)
        #expect(must.conditions.count == 1)
        let condition = try #require(must.conditions.first)
        #expect(condition.comparison == .equal)
        #expect(condition.flags.contains(.or))
        #expect(condition.comparisonValue == .value(1))
        #expect(condition.functionIndex == 576)
        #expect(condition.parameter1.rawValue == 0x0001_0800)
        #expect(condition.runOn == .target)
    }

    @Test func skipsMalformedConditionFields() throws {
        // A wrong-width CTDA is a mod quirk: drop the condition, keep the rest.
        let fields = ESMFixture.field("CITC", uint32(1))
            + ESMFixture.field("CTDA", Data(count: 20))
            + ESMFixture.field("ANAM", ESMFixture.zstring("Music\\mus.xwm"))
        let must = try MusicTrack(record: record(ESMFixture.record(
            "MUST", formID: 0x106, data: fields
        )))
        #expect(must.conditions.isEmpty)
        #expect(must.declaredConditionCount == 1)
        #expect(must.trackFileName == "Music\\mus.xwm")
    }

    @Test func wrongMusicTrackRecordTypeThrows() throws {
        #expect(throws: ESMError.self) {
            _ = try MusicTrack(record: record(ESMFixture.record("MUSC", data: Data())))
        }
    }

    // MARK: - Helpers

    private func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }
}
