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

    @Test func dumpsReferenceRotationAndTeleportPose() throws {
        var name = Data()
        name.appendUInt32(0x100)
        var placement = Data()
        for value: Float in [1, 2, 3, 0.1, 0.2, 0.3] {
            placement.appendFloat32(value)
        }
        var teleport = Data()
        teleport.appendUInt32(0x200)
        for value: Float in [4, 5, 6, 0.4, 0.5, 0.6] {
            teleport.appendFloat32(value)
        }
        teleport.appendUInt32(0)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("XTEL", teleport)
            + ESMFixture.field("DATA", placement)
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup(
            "REFR",
            contents: ESMFixture.record("REFR", formID: 0xABC, data: fields)
        )
        let dump = try RecordTextDump.dump(record: firstRecord(in: plugin), localized: false)
        #expect(dump.contains("rotation (0.1, 0.2, 0.3)"))
        #expect(dump.contains("teleport 00000200 at SIMD3<Float>(4.0, 5.0, 6.0)"))
        #expect(dump.contains("rotation SIMD3<Float>(0.4, 0.5, 0.6)"))
    }
}
