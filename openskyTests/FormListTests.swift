// Synthetic FLST decoder coverage. No game-derived bytes.

import Foundation
@testable import opensky
import Testing

struct FormListTests {
    @Test
    func decodesEditorIDAndPreservesEntryOrderIncludingNull() throws {
        let record = try Self.record(
            formID: 0x100,
            editorID: "OrderedForms",
            entries: [3, 0, 1, 2]
        )

        let list = try FormList(record: record)

        #expect(list.formID == FormID(0x100))
        #expect(list.editorID == "OrderedForms")
        #expect(list.entries == [FormID(3), nil, FormID(1), FormID(2)])
        #expect(list.malformedEntryCount == 0)
    }

    @Test
    func decodesAnEmptyList() throws {
        let list = try FormList(record: Self.record(formID: 0x100, editorID: "Empty"))

        #expect(list.entries.isEmpty)
        #expect(list.malformedEntryCount == 0)
    }

    @Test
    func dropsAndTalliesATruncatedTailEntry() throws {
        var fields = ESMFixture.field("LNAM", Self.uint32(1))
        fields += ESMFixture.field("LNAM", Data([2, 0, 0]))
        let record = try Self.parse(
            ESMFixture.record("FLST", formID: 0x100, data: fields)
        )

        let list = try FormList(record: record)

        #expect(list.entries == [FormID(1)])
        #expect(list.malformedEntryCount == 1)
    }

    @Test
    func rejectsAnotherRecordType() throws {
        let record = try Self.parse(ESMFixture.record("KYWD", formID: 1, data: Data()))

        #expect(throws: (any Error).self) { try FormList(record: record) }
    }

    static func record(
        formID: UInt32,
        editorID: String? = nil,
        entries: [UInt32] = []
    ) throws -> ESMRecord {
        try parse(recordBytes(formID: formID, editorID: editorID, entries: entries))
    }

    static func recordBytes(
        formID: UInt32,
        editorID: String? = nil,
        entries: [UInt32] = []
    ) -> Data {
        var fields = Data()
        if let editorID {
            fields += ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        }
        for entry in entries {
            fields += ESMFixture.field("LNAM", uint32(entry))
        }
        return ESMFixture.record("FLST", formID: formID, data: fields)
    }

    static func parse(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
