// Record decoder tests (WRLD, CELL, REFR, STAT, LString) over synthetic
// in-code records (ESMFixture) — never extracted game files (AGENTS.md
// "Legal & IP boundary"). Layouts: UESP "Skyrim Mod:Mod File Format" per-
// record pages; see docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

struct RecordDecoderTests {
    /// Parses one synthetic record through the container walk.
    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    // MARK: - LString

    @Test func lstringDecodesInlineWhenNotLocalized() throws {
        let field = ESMField(type: "FULL", data: ESMFixture.zstring("Whiterun"))
        #expect(try LString(field: field, localized: false) == .inline("Whiterun"))
    }

    @Test func lstringDecodesTableIDWhenLocalized() throws {
        var data = Data()
        data.appendUInt32(0x0001_2345)
        let field = ESMField(type: "FULL", data: data)
        #expect(try LString(field: field, localized: true) == .tableID(0x0001_2345))
    }

    @Test func lstringRejectsTruncatedField() {
        let field = ESMField(type: "FULL", data: Data([0x01, 0x02]))
        #expect(throws: (any Error).self) {
            _ = try LString(field: field, localized: true)
        }
        #expect(throws: (any Error).self) {
            // Unterminated inline zstring.
            _ = try LString(field: field, localized: false)
        }
    }

    // MARK: - WRLD

    @Test func decodesWorldspace() throws {
        var full = Data()
        full.appendUInt32(0x42)
        var wnam = Data()
        wnam.appendUInt32(0x3C)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Tamriel"))
            + ESMFixture.field("FULL", full)
            + ESMFixture.field("WNAM", wnam)
            + ESMFixture.field("DATA", Data([0x02]))
            + ESMFixture.field("ZNAM", Data(count: 4)) // skipped
        let world = try Worldspace(
            record: record(ESMFixture.record("WRLD", formID: 0x3C, data: fields)),
            localized: true
        )
        #expect(world.formID == FormID(0x3C))
        #expect(world.editorID == "Tamriel")
        #expect(world.name == .tableID(0x42))
        #expect(world.parent == FormID(0x3C))
        #expect(world.flags == .noFastTravel)
    }

    @Test func decodesMinimalWorldspace() throws {
        let world = try Worldspace(
            record: record(ESMFixture.record("WRLD", formID: 0x1A, data: Data())),
            localized: false
        )
        #expect(world.editorID == nil)
        #expect(world.name == nil)
        #expect(world.parent == nil)
        #expect(world.flags.isEmpty)
    }

    @Test func worldspaceRejectsWrongRecordType() throws {
        let statBytes = ESMFixture.record("STAT", data: Data())
        #expect(throws: (any Error).self) {
            _ = try Worldspace(record: record(statBytes), localized: false)
        }
    }

    // MARK: - CELL

    @Test func decodesExteriorCell() throws {
        var xclc = Data()
        xclc.appendUInt32(UInt32(bitPattern: -3))
        xclc.appendUInt32(UInt32(bitPattern: 7))
        xclc.appendUInt32(0x53FD_0001) // high bits are CK noise, kept verbatim
        var data = Data()
        data.appendUInt16(0x0002)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Wilderness"))
            + ESMFixture.field("DATA", data)
            + ESMFixture.field("XCLC", xclc)
        let cell = try Cell(
            record: record(ESMFixture.record("CELL", formID: 0x2B, data: fields)),
            localized: true
        )
        #expect(cell.editorID == "Wilderness")
        #expect(!cell.isInterior)
        #expect(cell.flags.contains(.hasWater))
        #expect(cell.grid == Cell.Grid(x: -3, y: 7, quadFlags: 0x53FD_0001))
    }

    @Test func decodesInteriorCellWithOneByteFlags() throws {
        var full = Data()
        full.appendUInt32(0x99)
        let fields = ESMFixture.field("DATA", Data([0x01]))
            + ESMFixture.field("FULL", full)
        let cell = try Cell(
            record: record(ESMFixture.record("CELL", data: fields)),
            localized: true
        )
        #expect(cell.isInterior)
        #expect(cell.name == .tableID(0x99))
        #expect(cell.grid == nil)
    }

    @Test func decodesEightByteXCLC() throws {
        var xclc = Data()
        xclc.appendUInt32(UInt32(bitPattern: 5))
        xclc.appendUInt32(UInt32(bitPattern: -9))
        let fields = ESMFixture.field("XCLC", xclc)
        let cell = try Cell(
            record: record(ESMFixture.record("CELL", data: fields)),
            localized: false
        )
        #expect(cell.grid == Cell.Grid(x: 5, y: -9, quadFlags: 0))
    }

    @Test func decodesCompressedCell() throws {
        var data = Data()
        data.appendUInt16(0x0001)
        let fields = ESMFixture.field("DATA", data)
        let cell = try Cell(
            record: record(ESMFixture.compressedRecord("CELL", formID: 0x7, fieldData: fields)),
            localized: true
        )
        #expect(cell.formID == FormID(0x7))
        #expect(cell.isInterior)
    }

    // MARK: - REFR

    @Test func decodesPlacedReference() throws {
        var name = Data()
        name.appendUInt32(0x0002_D4E2)
        var data = Data()
        for value: Float in [4096.5, -8192.25, 128, 0.5, -1.5, 3.14] {
            data.appendUInt32(value.bitPattern)
        }
        var xscl = Data()
        xscl.appendUInt32(Float(1.5).bitPattern)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", data)
            + ESMFixture.field("XSCL", xscl)
        let refr = try PlacedReference(
            record: record(ESMFixture.record("REFR", formID: 0x1000, data: fields))
        )
        #expect(refr.base == FormID(0x0002_D4E2))
        #expect(refr.placement.position == SIMD3(4096.5, -8192.25, 128))
        #expect(refr.placement.rotation == SIMD3(0.5, -1.5, 3.14))
        #expect(refr.scale == 1.5)
    }

    @Test func placedReferenceScaleDefaultsToOne() throws {
        var name = Data()
        name.appendUInt32(0x1)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", Data(count: 24))
        let refr = try PlacedReference(
            record: record(ESMFixture.record("REFR", data: fields))
        )
        #expect(refr.scale == 1)
        #expect(refr.placement.position == SIMD3(0, 0, 0))
    }

    @Test func placedReferenceRequiresNameAndData() throws {
        var name = Data()
        name.appendUInt32(0x1)
        let onlyName = ESMFixture.record("REFR", data: ESMFixture.field("NAME", name))
        let onlyData = ESMFixture.record("REFR", data: ESMFixture.field("DATA", Data(count: 24)))
        #expect(throws: (any Error).self) {
            _ = try PlacedReference(record: record(onlyName))
        }
        #expect(throws: (any Error).self) {
            _ = try PlacedReference(record: record(onlyData))
        }
    }

    // MARK: - STAT

    @Test func decodesStaticObject() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("WRTempleofKynareth"))
            + ESMFixture.field("MODL", ESMFixture.zstring("Meshes\\Clutter\\Cup01.nif"))
            + ESMFixture.field("MODT", Data(count: 12)) // skipped
        let stat = try StaticObject(
            record: record(ESMFixture.record("STAT", formID: 0x5F, data: fields))
        )
        #expect(stat.formID == FormID(0x5F))
        #expect(stat.editorID == "WRTempleofKynareth")
        #expect(stat.modelPath == "Meshes\\Clutter\\Cup01.nif")
    }

    @Test func staticObjectWithoutModelIsMarker() throws {
        let stat = try StaticObject(
            record: record(ESMFixture.record("STAT", data: Data()))
        )
        #expect(stat.modelPath == nil)
    }

    // MARK: - ModelBase (MSTT/TREE/FURN/ACTI/CONT)

    @Test func decodesModelBaseForEachSupportedType() throws {
        for type in ["MSTT", "TREE", "FURN", "ACTI", "CONT"] {
            let fields = ESMFixture.field("EDID", ESMFixture.zstring("Some\(type)"))
                + ESMFixture.field("MODL", ESMFixture.zstring("Meshes\\\(type)\\thing.nif"))
            let base = try ModelBase(
                record: record(ESMFixture.record(type, formID: 0x77, data: fields))
            )
            #expect(base.formID == FormID(0x77))
            #expect(base.recordType == FourCC(stringLiteral: type))
            #expect(base.editorID == "Some\(type)")
            #expect(base.modelPath == "Meshes\\\(type)\\thing.nif")
        }
    }

    @Test func modelBaseWithoutModelIsMarker() throws {
        let base = try ModelBase(
            record: record(ESMFixture.record("TREE", data: Data()))
        )
        #expect(base.modelPath == nil)
    }

    @Test func modelBaseRejectsUnsupportedRecordType() throws {
        let statBytes = ESMFixture.record("STAT", data: Data())
        #expect(throws: (any Error).self) {
            _ = try ModelBase(record: record(statBytes))
        }
    }
}
