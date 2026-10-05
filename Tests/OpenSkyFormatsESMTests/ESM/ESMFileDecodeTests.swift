// `ESMFile` decode helpers and `SkippedRecords` over synthetic plugins: a
// record or group that fails to parse is counted, never dropped silently.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ESMFileDecodeTests {
    private static let deletedFlag: UInt32 = 0x20

    private func plugin() throws -> ESMFile {
        let good = ESMFixture.record(
            "GLOB",
            formID: 0x10,
            data: ESMFixture.field("EDID", ESMFixture.zstring("Good"))
        )
        let deleted = ESMFixture.record("GLOB", formID: 0x11, flags: Self.deletedFlag, data: Data())
        let broken = ESMFixture.malformedRecord("GLOB", formID: 0x12)
        return try ESMFile(
            data: ESMFixture.tes4() + ESMFixture.topGroup("GLOB", contents: good + deleted + broken)
        )
    }

    @Test func countsAThrowingDecodeAndSkipsDeletedRecords() throws {
        var skipped = SkippedRecords()
        let counts = try plugin().decodeRecords(of: "GLOB", skipped: &skipped) {
            try $0.fields().count
        }
        #expect(counts == [1])
        #expect(skipped.count(of: "GLOB") == 1)
        #expect(skipped.total == 1)
    }

    @Test func indexesByRecordFormID() throws {
        var skipped = SkippedRecords()
        let index = try plugin().indexRecords(of: "GLOB", skipped: &skipped) {
            try $0.fields().first?.type
        }
        #expect(index == [0x10: "EDID"])
        #expect(skipped.count(of: "GLOB") == 1)
    }

    @Test func aMissingGroupDecodesNothing() throws {
        var skipped = SkippedRecords()
        let values = try plugin().decodeRecords(of: "MOVT", skipped: &skipped) { $0.formID }
        #expect(values.isEmpty)
        #expect(skipped.isEmpty)
    }

    @Test func liveRecordsLeavesOutDeletedRecords() throws {
        var skipped = SkippedRecords()
        let records = try plugin().liveRecords(of: "GLOB", skipped: &skipped)
        #expect(records.map(\.formID) == [0x10, 0x12])
        #expect(skipped.isEmpty)
    }

    @Test func aTruncatedGroupIsNotedUnderItsRecordType() throws {
        let file = try ESMFile(
            data: ESMFixture.tes4() + ESMFixture.topGroup("GLOB", contents: Data(count: 10))
        )
        var skipped = SkippedRecords()
        let group = try #require(file.topGroup(of: "GLOB"))
        let children = skipped.children(of: group)
        let records = file.liveRecords(of: "GLOB", skipped: &skipped)
        #expect(children.isEmpty)
        #expect(records.isEmpty)
        #expect(skipped.count(of: "GLOB") == 2)
    }

    @Test func mastersNotesAHeaderWithoutHEDR() throws {
        let file = try ESMFile(data: ESMFixture.record("TES4", flags: 0x80, data: Data()))
        var skipped = SkippedRecords()
        let masters = skipped.masters(of: file)
        #expect(masters.isEmpty)
        #expect(skipped.count(of: "TES4") == 1)
        // The localized flag lives in the record header, so it still reads.
        #expect(file.isLocalized)
    }

    @Test func mastersReadsAValidHeader() throws {
        let file = try ESMFile(data: ESMFixture.tes4(masters: ["Skyrim.esm"]))
        var skipped = SkippedRecords()
        let masters = skipped.masters(of: file)
        #expect(masters == ["Skyrim.esm"])
        #expect(skipped.isEmpty)
        #expect(!file.isLocalized)
    }
}
