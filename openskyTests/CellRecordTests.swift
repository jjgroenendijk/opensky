// Cell decoder unit tests. Covers the XCAS acoustic-space field added in
// M9.2.2 (issue #155) and a baseline decode to anchor coverage. Cell had no
// dedicated unit-test file before this — synthetic fixtures only.

import Foundation
@testable import opensky
import Testing

struct CellRecordTests {
    @Test func decodesAcousticSpaceField() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Interior"))
            + ESMFixture.field("DATA", Data([0x01, 0x00])) // interior flag
            + ESMFixture.field("XCAS", formID(0xABC))
        let cell = try Cell(record: record(ESMFixture.record(
            "CELL", formID: 0x10, data: fields
        )), localized: false)

        #expect(cell.acousticSpace == FormID(0xABC))
        #expect(cell.isInterior)
    }

    @Test func acousticSpaceNilWhenAbsent() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Quiet"))
            + ESMFixture.field("DATA", Data([0x01, 0x00]))
        let cell = try Cell(record: record(ESMFixture.record(
            "CELL", formID: 0x11, data: fields
        )), localized: false)

        #expect(cell.acousticSpace == nil)
    }

    @Test func skipsTruncatedAcousticSpaceField() throws {
        // XCAS with <4 bytes -> nil, not malformed-throw.
        let fields = ESMFixture.field("XCAS", Data([1, 2]))
        let cell = try Cell(record: record(ESMFixture.record(
            "CELL", formID: 0x12, data: fields
        )), localized: false)

        #expect(cell.acousticSpace == nil)
    }

    @Test func exteriorGridAndFlagsDecode() throws {
        var xclc = Data()
        xclc.appendUInt32(UInt32(bitPattern: Int32(4)))
        xclc.appendUInt32(UInt32(bitPattern: Int32(-3)))
        xclc.appendUInt32(0) // quad flags
        let fields = ESMFixture.field("DATA", Data([0x00, 0x00]))
            + ESMFixture.field("XCLC", xclc)
        let cell = try Cell(record: record(ESMFixture.record(
            "CELL", formID: 0x13, data: fields
        )), localized: false)

        #expect(!cell.isInterior)
        let grid = try #require(cell.grid)
        #expect(grid.x == 4)
        #expect(grid.y == -3)
    }

    private func formID(_ value: UInt32) -> Data {
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
