// `ESMFile.decodeRecords` and `indexRecords` over synthetic plugins: a record
// whose decode throws is counted, and a deleted record is left out.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import Testing

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
}
