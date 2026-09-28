// Record decoder tests (WRLD, CELL, REFR, STAT, LString) over synthetic
// in-code records (ESMFixture) — never extracted game files (AGENTS.md
// "Legal & IP boundary"). Layouts: UESP "Skyrim Mod:Mod File Format" per-
// record pages; see docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

struct RecordDecoderTests {
    /// Parses one synthetic record through the container walk.
    func record(_ bytes: Data) throws -> ESMRecord {
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
        var pnam = Data()
        pnam.appendUInt16(0x0009)
        var dnam = Data()
        dnam.appendFloat32(-27000)
        dnam.appendFloat32(-14000)
        var nam2 = Data()
        nam2.appendUInt32(0x18)
        var cnam = Data()
        cnam.appendUInt32(0x2A) // climate FormID
        var znam = Data()
        znam.appendUInt32(0x2B) // music type FormID
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Tamriel"))
            + ESMFixture.field("FULL", full)
            + ESMFixture.field("WNAM", wnam)
            + ESMFixture.field("PNAM", pnam)
            + ESMFixture.field("DNAM", dnam)
            + ESMFixture.field("NAM2", nam2)
            + ESMFixture.field("CNAM", cnam)
            + ESMFixture.field("DATA", Data([0x02]))
            + ESMFixture.field("ZNAM", znam) // default music type (M9.2.3)
        let world = try Worldspace(
            record: record(ESMFixture.record("WRLD", formID: 0x3C, data: fields)),
            localized: true
        )
        #expect(world.formID == FormID(0x3C))
        #expect(world.editorID == "Tamriel")
        #expect(world.name == .tableID(0x42))
        #expect(world.parent == FormID(0x3C))
        #expect(world.parentFlags == [.useLandData, .useWaterData])
        #expect(world.flags == .noFastTravel)
        #expect(world.defaultLandHeight == -27000)
        #expect(world.defaultWaterHeight == -14000)
        #expect(world.waterType == FormID(0x18))
        #expect(world.climate == FormID(0x2A))
        #expect(world.musicType == FormID(0x2B))
    }

    @Test func worldspaceIgnoresNullMusicType() throws {
        let world = try Worldspace(
            record: record(ESMFixture.record(
                "WRLD", formID: 0x3D, data: ESMFixture.field("ZNAM", Data(count: 4))
            )),
            localized: false
        )
        #expect(world.musicType == nil)
    }

    @Test func decodesMinimalWorldspace() throws {
        let world = try Worldspace(
            record: record(ESMFixture.record("WRLD", formID: 0x1A, data: Data())),
            localized: false
        )
        #expect(world.editorID == nil)
        #expect(world.name == nil)
        #expect(world.parent == nil)
        #expect(world.parentFlags.isEmpty)
        #expect(world.flags.isEmpty)
        #expect(world.defaultWaterHeight == nil)
        #expect(world.waterType == nil)
        #expect(world.climate == nil)
        #expect(world.musicType == nil)
    }

    @Test func worldspaceRejectsWrongRecordType() throws {
        let statBytes = ESMFixture.record("STAT", data: Data())
        #expect(throws: (any Error).self) {
            _ = try Worldspace(record: record(statBytes), localized: false)
        }
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

    // MARK: - ModelBase (MSTT/TREE/FURN/ACTI/CONT/DOOR)
}

extension RecordDecoderTests {
    @Test func decodesDoorTeleportDestination() throws {
        var name = Data()
        name.appendUInt32(0x10)
        var xtel = Data()
        xtel.appendUInt32(0x000A_BCDE)
        for value: Float in [10, 20, 30, 0.25, -0.5, 1.5] {
            xtel.appendFloat32(value)
        }
        xtel.appendUInt32(0x1)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", Data(count: 24))
            + ESMFixture.field("XTEL", xtel)
        let refr = try PlacedReference(
            record: record(ESMFixture.record("REFR", formID: 0x20, data: fields))
        )
        let destination = try #require(refr.teleportDestination)
        #expect(destination.door == FormID(0x000A_BCDE))
        #expect(destination.placement.position == SIMD3(10, 20, 30))
        #expect(destination.placement.rotation == SIMD3(0.25, -0.5, 1.5))
        #expect(destination.flags == .noAlarm)
    }

    @Test func rejectsTruncatedDoorTeleportDestination() throws {
        var name = Data()
        name.appendUInt32(0x10)
        let fields = ESMFixture.field("NAME", name)
            + ESMFixture.field("DATA", Data(count: 24))
            + ESMFixture.field("XTEL", Data(count: 31))
        #expect(throws: (any Error).self) {
            _ = try PlacedReference(
                record: record(ESMFixture.record("REFR", formID: 0x20, data: fields))
            )
        }
    }
}
