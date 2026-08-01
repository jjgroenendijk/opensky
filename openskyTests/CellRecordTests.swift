// CELL decoder tests over synthetic in-code records only. Covers field layout
// variants and malformed-payload policy without using extracted game data.

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

    @Test func decodesExteriorFieldsAndTwelveByteGrid() throws {
        var flags = Data()
        flags.appendUInt16(Cell.Flags.hasWater.rawValue)
        var xclc = Data()
        xclc.appendUInt32(UInt32(bitPattern: -3))
        xclc.appendUInt32(UInt32(bitPattern: 7))
        xclc.appendUInt32(0x53FD_0001)
        var xclw = Data()
        xclw.appendFloat32(-14000)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Wilderness"))
            + ESMFixture.field("DATA", flags)
            + ESMFixture.field("XCLC", xclc)
            + ESMFixture.field("XCLW", xclw)
            + ESMFixture.field("XCWT", formID(0x18))
        let cell = try Cell(record: record(ESMFixture.record(
            "CELL", formID: 0x2B, data: fields
        )), localized: false)

        #expect(cell.editorID == "Wilderness")
        #expect(!cell.isInterior)
        #expect(cell.flags == .hasWater)
        #expect(cell.grid == Cell.Grid(x: -3, y: 7, quadFlags: 0x53FD_0001))
        #expect(cell.waterHeight == .height(-14000))
        #expect(cell.waterType == FormID(0x18))
    }

    @Test func decodesEightByteGridWithoutQuadFlags() throws {
        var xclc = Data()
        xclc.appendUInt32(UInt32(bitPattern: 5))
        xclc.appendUInt32(UInt32(bitPattern: -9))
        let cell = try Cell(record: record(ESMFixture.record(
            "CELL", data: ESMFixture.field("XCLC", xclc)
        )), localized: false)

        #expect(cell.grid == Cell.Grid(x: 5, y: -9, quadFlags: 0))
    }

    @Test func decodesOneAndTwoByteDataFlags() throws {
        var full = Data()
        full.appendUInt32(0x99)
        let oneByteFields = ESMFixture.field("DATA", Data([0xA1]))
            + ESMFixture.field("FULL", full)
        let oneByte = try Cell(record: record(ESMFixture.record(
            "CELL", data: oneByteFields
        )), localized: true)
        var twoByteData = Data()
        twoByteData.appendUInt16(0x010C)
        let twoByte = try Cell(record: record(ESMFixture.record(
            "CELL", data: ESMFixture.field("DATA", twoByteData)
        )), localized: false)

        #expect(oneByte.flags.rawValue == 0x00A1)
        #expect(oneByte.isInterior)
        #expect(oneByte.name == .tableID(0x99))
        #expect(oneByte.grid == nil)
        #expect(twoByte.flags.rawValue == 0x010C)
        #expect(twoByte.flags.contains(.useSkyLighting))
    }

    @Test func recognizesAllNoWaterSentinels() throws {
        for bits: UInt32 in [0x7F7F_FFFF, 0x4F7F_FFC9, 0xCF00_0000] {
            let cell = try Cell(record: record(ESMFixture.record(
                "CELL", data: ESMFixture.field("XCLW", formID(bits))
            )), localized: false)

            #expect(cell.waterHeight == .noWater)
        }
    }

    @Test func decodesRegionArray() throws {
        let regions = formID(0x101) + formID(0x102) + formID(0x103)
        let cell = try Cell(record: record(ESMFixture.record(
            "CELL", data: ESMFixture.field("XCLR", regions)
        )), localized: false)

        #expect(cell.regions == [FormID(0x101), FormID(0x102), FormID(0x103)])
    }

    @Test func rejectsMisalignedRegionArrayWithoutPartialResults() throws {
        let regions = formID(0x101) + Data([0x02])
        let cell = try Cell(record: record(ESMFixture.record(
            "CELL", data: ESMFixture.field("XCLR", regions)
        )), localized: false)

        #expect(cell.regions.isEmpty)
    }

    @Test func decodesFullInteriorLightingAndTemplateReference() throws {
        let fields = ESMFixture.field("DATA", Data([UInt8(Cell.Flags.interior.rawValue)]))
            + ESMFixture.field("XCLL", ESMFixture.cellLightingData(inherits: 0x0615))
            + ESMFixture.field("LTMP", formID(0x0006_175D))
        let cell = try Cell(record: record(ESMFixture.record(
            "CELL", formID: 0x16204, data: fields
        )), localized: false)

        #expect(cell.lightingTemplate == FormID(0x0006_175D))
        let lighting = try #require(cell.lighting)
        #expect(lighting.ambientColor == color(10, 20, 30))
        #expect(lighting.directionalColor == color(40, 50, 60))
        #expect(lighting.fogNearColor == color(70, 80, 90))
        #expect(lighting.fogNear == 100)
        #expect(lighting.fogFar == 900)
        #expect(lighting.directionalRotationXY == 180)
        #expect(lighting.directionalRotationZ == -45)
        #expect(lighting.directionalAmbient?.positiveX == color(1, 2, 3))
        #expect(lighting.fogFarColor == color(91, 92, 93))
        #expect(lighting.fogMax == 0.75)
        #expect(lighting.lightFadeBegin == 250)
        #expect(lighting.lightFadeEnd == 750)
        #expect(lighting.inherits.rawValue == 0x0615)
    }

    @Test func acceptsKnownTruncatedLightingTails() throws {
        let full = ESMFixture.cellLightingData(inherits: 0)
        for count in [40, 64, 68, 72, 76, 80, 84, 88, 92] {
            let cell = try Cell(record: record(ESMFixture.record(
                "CELL", data: ESMFixture.field("XCLL", Data(full.prefix(count)))
            )), localized: false)
            #expect(cell.lighting != nil)
        }

        let tooShort = try Cell(record: record(ESMFixture.record(
            "CELL", data: ESMFixture.field("XCLL", Data(full.prefix(39)))
        )), localized: false)
        #expect(tooShort.lighting == nil)
    }

    @Test func decodesCompressedCell() throws {
        var data = Data()
        data.appendUInt16(Cell.Flags.interior.rawValue)
        let fields = ESMFixture.field("DATA", data)
        let cell = try Cell(record: record(ESMFixture.compressedRecord(
            "CELL", formID: 0x7, fieldData: fields
        )), localized: false)

        #expect(cell.formID == FormID(0x7))
        #expect(cell.isInterior)
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

    private func color(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> SIMD3<Float> {
        SIMD3(Float(red) / 255, Float(green) / 255, Float(blue) / 255)
    }
}
