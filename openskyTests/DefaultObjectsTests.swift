// Synthetic DOBJ decode and entry-granular override tests. Layout and tags:
// UESP DOBJ and xEdit dev-4.1.6 wbDOBJObjectsTES5 / wbRecord(DOBJ, ...).

import Foundation
@testable import opensky
import Testing

struct DefaultObjectsTests {
    @Test func decodesKnownAndUnknownTagsAndWrongTypeThrows() throws {
        let defaults = try DefaultObjects(record: record(
            type: "DOBJ",
            fields: ESMFixture.field("DNAM", entries([
                ("GOLD", 0x0F), ("ZZZZ", 0x20), (nil, 0)
            ]))
        ))
        #expect(defaults.editorID == "DefaultObjectManager")
        #expect(defaults.entries.count == 2)
        #expect(defaults.entry(tag: "GOLD")?.object == FormID(0x0F))
        #expect(defaults.entry(tag: "GOLD")?.tag.meaning == "Gold")
        let unknown = try #require(DefaultObjectTag(name: "ZZZZ"))
        #expect(defaults.skipped.counts[.unknownDefaultObjectTag(unknown.code)] == 1)

        let wrong = try record(type: "KYWD", fields: Data())
        #expect(throws: ESMError.self) { try DefaultObjects(record: wrong) }
    }

    @Test func truncatedPackedArrayKeepsCompleteEntriesAndTalliesTail() throws {
        let payload = entries([("GOLD", 0x0F)]) + Data([1, 2, 3])
        let defaults = try DefaultObjects(record: record(
            type: "DOBJ", fields: ESMFixture.field("DNAM", payload)
        ))
        #expect(defaults.entries.count == 1)
        #expect(defaults.skipped.counts[.malformedField("DNAM")] == 1)
    }

    @Test func storeMergesOverridesByTagAndResolvesTheirAuthoringPlugin() throws {
        let base = try plugin(records: [ESMFixture.record(
            "DOBJ", formID: 0x31,
            data: ESMFixture.field("DNAM", entries([
                ("GOLD", 0x0F), ("LKPK", 0x0A)
            ]))
        )])
        let patch = try plugin(
            masters: ["Base.esm"],
            records: [ESMFixture.record(
                "DOBJ", formID: 0x31,
                data: ESMFixture.field("DNAM", entries([
                    (nil, 0), ("GOLD", 0x0100_0020)
                ]))
            )]
        )
        let store = DefaultObjectStore(plugins: [
            ("Base.esm", base), ("Patch.esp", patch)
        ])
        #expect(store.object(tag: "GOLD") == ResolvedFormID(
            plugin: "Patch.esp", objectID: 0x20
        ))
        #expect(store.entry(tag: "GOLD")?.sourcePlugin == "Patch.esp")
        #expect(store.object(tag: "LKPK") == ResolvedFormID(
            plugin: "Base.esm", objectID: 0x0A
        ))
        #expect(store.defaultObjects(editorID: "DEFAULTOBJECTMANAGER")?.sourcePlugin
            == "Patch.esp")
        #expect(store.defaultObjects(ResolvedFormID(
            plugin: "Base.esm", objectID: 0x31
        ))?.record.entries.count == 1)
    }

    private func entries(_ values: [(String?, UInt32)]) -> Data {
        var data = Data()
        for value in values {
            if let tag = value.0 {
                data.append(contentsOf: tag.utf8)
            } else {
                data.appendUInt32(0)
            }
            data.appendUInt32(value.1)
        }
        return data
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
        type: String = "DOBJ",
        records: [Data]
    ) throws -> ESMFile {
        try ESMFile(data: ESMFixture.tes4(masters: masters)
            + ESMFixture.topGroup(type, contents: records.reduce(Data(), +)))
    }
}
