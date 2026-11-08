// Synthetic FLST decoder coverage. No game-derived bytes.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct FormListTests {
    @Test
    func decodesEditorIDAndPreservesEntryOrderIncludingNull() throws {
        let record = try FormListFixture.record(
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
    func throwsOnAnUnterminatedEditorID() throws {
        let fields = ESMFixture.field("EDID", Data("NoTerminator".utf8))
        let record = try FormListFixture.parse(
            ESMFixture.record("FLST", formID: 0x100, data: fields)
        )

        #expect(throws: BinaryReaderError.self) { try FormList(record: record) }
    }

    @Test
    func decodesAnEmptyList() throws {
        let list = try FormList(record: FormListFixture.record(formID: 0x100, editorID: "Empty"))

        #expect(list.entries.isEmpty)
        #expect(list.malformedEntryCount == 0)
    }

    @Test
    func dropsAndTalliesATruncatedTailEntry() throws {
        var fields = ESMFixture.field("LNAM", FormListFixture.uint32(1))
        fields += ESMFixture.field("LNAM", Data([2, 0, 0]))
        let record = try FormListFixture.parse(
            ESMFixture.record("FLST", formID: 0x100, data: fields)
        )

        let list = try FormList(record: record)

        #expect(list.entries == [FormID(1)])
        #expect(list.malformedEntryCount == 1)
    }

    @Test
    func rejectsAnotherRecordType() throws {
        let record = try FormListFixture.parse(ESMFixture.record("KYWD", formID: 1, data: Data()))

        #expect(throws: (any Error).self) { try FormList(record: record) }
    }
}
