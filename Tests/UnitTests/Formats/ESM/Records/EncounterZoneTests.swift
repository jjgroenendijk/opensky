// Synthetic ECZN decode and load-order tests. Layout: UESP ECZN, cross-
// checked against xEdit dev-4.1.6 wbDefinitionsTES5.pas lines 6286-6306.

import Foundation
@testable import opensky
import Testing

struct EncounterZoneTests {
    @Test func decodesPackedDataAndToleratesTruncation() throws {
        let full = try EncounterZone(record: record(
            type: "ECZN",
            fields: zoneFields(editorID: "BleakFallsBarrowZone", data: zoneData())
        ))
        #expect(full.editorID == "BleakFallsBarrowZone")
        #expect(full.owner == FormID(0x10))
        #expect(full.location == FormID(0x20))
        #expect(full.rank == -1)
        #expect(full.minimumLevel == 6)
        #expect(full.flags.contains(.matchesPlayerBelowMinimumLevel))
        #expect(full.maximumLevel == 24)

        let short = try EncounterZone(record: record(
            type: "ECZN",
            fields: zoneFields(editorID: "LegacyZone", data: zoneData().prefixData(8))
        ))
        #expect(short.owner == FormID(0x10))
        #expect(short.location == FormID(0x20))
        #expect(short.rank == nil)
        #expect(short.maximumLevel == nil)

        let veryShort = try EncounterZone(record: record(
            type: "ECZN",
            fields: zoneFields(editorID: "ModZone", data: Data([1, 2, 3]))
        ))
        #expect(veryShort.owner == nil)
        #expect(veryShort.skipped.total == 0)
    }

    @Test func wrongRecordTypeThrows() throws {
        let wrong = try record(type: "KYWD", fields: Data())
        #expect(throws: ESMError.self) { try EncounterZone(record: wrong) }
    }

    @Test func storeUsesResolvedIdentityAndWiresCellAndWorldLinks() throws {
        let base = try plugin(
            type: "ECZN",
            records: [ESMFixture.record(
                "ECZN", formID: 0x42,
                data: zoneFields(editorID: "BaseZone", data: zoneData())
            )]
        )
        let patch = try plugin(
            masters: ["Base.esm"],
            type: "ECZN",
            records: [ESMFixture.record(
                "ECZN", formID: 0x42,
                data: zoneFields(editorID: "PatchedZone", data: zoneData())
            )]
        )
        let store = EncounterZoneStore(plugins: [
            ("Base.esm", base), ("Patch.esp", patch)
        ])
        let id = ResolvedFormID(plugin: "Base.esm", objectID: 0x42)
        #expect(store.zone(id)?.zone.editorID == "PatchedZone")
        #expect(store.zone(editorID: "PATCHEDZONE")?.sourcePlugin == "Patch.esp")

        var link = Data()
        link.appendUInt32(0x42)
        let cell = try Cell(
            record: record(type: "CELL", fields: ESMFixture.field("XEZN", link)),
            localized: false
        )
        let world = try Worldspace(
            record: record(type: "WRLD", fields: ESMFixture.field("XEZN", link)),
            localized: false
        )
        #expect(store.encounterZone(containing: cell, fromPlugin: "Patch.esp")?.id == id)
        #expect(store.encounterZone(for: world, fromPlugin: "Patch.esp")?.id == id)
    }

    private func zoneData() -> Data {
        var data = Data()
        data.appendUInt32(0x10)
        data.appendUInt32(0x20)
        data.append(UInt8(bitPattern: -1))
        data.append(6)
        data.append(0x02)
        data.append(24)
        return data
    }

    private func zoneFields(editorID: String, data: Data) -> Data {
        ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("DATA", data)
    }

    private func record(type: String, fields: Data) throws -> ESMRecord {
        let file = try plugin(type: type, records: [
            ESMFixture.record(type, formID: 1, data: fields)
        ])
        let group = try #require(file.topGroups.first)
        let children = try group.children()
        guard case let .record(record) = try #require(children.first) else {
            throw ESMError.malformed("fixture record missing")
        }
        return record
    }

    private func plugin(
        masters: [String] = [],
        type: String,
        records: [Data]
    ) throws -> ESMFile {
        try ESMFile(data: ESMFixture.tes4(masters: masters)
            + ESMFixture.topGroup(type, contents: records.reduce(Data(), +)))
    }
}

extension Data {
    fileprivate func prefixData(_ count: Int) -> Data {
        Data(prefix(count))
    }
}
