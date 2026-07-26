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

    @Test func decodesMusicTypeField() throws {
        // XCMO (M9.2.3): MUSC override, decoded alongside the other links.
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Tavern"))
            + ESMFixture.field("DATA", Data([0x01, 0x00]))
            + ESMFixture.field("XCAS", formID(0xABC))
            + ESMFixture.field("XCMO", formID(0xDEF))
        let cell = try Cell(record: record(ESMFixture.record(
            "CELL", formID: 0x14, data: fields
        )), localized: false)

        #expect(cell.musicType == FormID(0xDEF))
        #expect(cell.acousticSpace == FormID(0xABC))
    }

    @Test func musicTypeNilWhenAbsentNullOrTruncated() throws {
        let bare = try Cell(record: record(ESMFixture.record(
            "CELL", formID: 0x15, data: ESMFixture.field("DATA", Data([0x01, 0x00]))
        )), localized: false)
        #expect(bare.musicType == nil)

        let null = try Cell(record: record(ESMFixture.record(
            "CELL", formID: 0x16, data: ESMFixture.field("XCMO", formID(0))
        )), localized: false)
        #expect(null.musicType == nil)

        let short = try Cell(record: record(ESMFixture.record(
            "CELL", formID: 0x17, data: ESMFixture.field("XCMO", Data([1, 2]))
        )), localized: false)
        #expect(short.musicType == nil)
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
