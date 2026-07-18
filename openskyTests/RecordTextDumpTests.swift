// Shared record-dump tests (CLI `record` + Asset Browser detail): header line,
// decoded view, zstring rendering, field cap. In-code plugin fixtures only.

import Foundation
@testable import opensky
import Testing

struct RecordTextDumpTests {
    private func firstRecord(in plugin: Data) throws -> ESMRecord {
        let file = try ESMFile(data: plugin)
        var found: ESMRecord?
        ESMWalk.forEachRecord(in: file) { record in
            found = record
            return false
        }
        return try #require(found)
    }

    @Test func dumpsDecodedSTATWithFields() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("TestStatic"))
            + ESMFixture.field("MODL", ESMFixture.zstring("clutter\\cup.nif"))
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup(
            "STAT",
            contents: ESMFixture.record("STAT", formID: 0xABC, data: fields)
        )
        let dump = try RecordTextDump.dump(record: firstRecord(in: plugin), localized: false)
        #expect(dump.contains("STAT 00000ABC"))
        #expect(dump.contains("decoded STAT: editorID TestStatic, model clutter\\cup.nif"))
        #expect(dump.contains("fields (2):"))
        #expect(dump.contains("EDID 11 bytes \"TestStatic\""))
    }

    @Test func capsLongFieldLists() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("Big"))
        for _ in 0 ..< 70 {
            fields += ESMFixture.field("RNAM", Data([1, 2, 3, 4]))
        }
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup(
            "TSTA",
            contents: ESMFixture.record("TSTA", formID: 1, data: fields)
        )
        let dump = try RecordTextDump.dump(record: firstRecord(in: plugin), localized: false)
        #expect(dump.contains("fields (71):"))
        #expect(dump.contains("... 7 more: RNAM 7"))
    }
}
