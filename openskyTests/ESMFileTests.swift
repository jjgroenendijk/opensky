// ESM/ESP container-walk tests over synthetic in-code plugins (ESMFixture).

import Foundation
@testable import opensky
import Testing

struct ESMFileTests {
    @Test func parsesTES4HeaderRecord() throws {
        let file = try ESMFile(data: ESMFixture.tes4())
        #expect(file.tes4.type == "TES4")
        #expect(file.tes4.flags.contains(.esm))
        #expect(file.tes4.header.version == 44)
        #expect(file.topGroups.isEmpty)

        let fields = try file.tes4.fields()
        #expect(fields.count == 1)
        #expect(fields.first?.type == "HEDR")
        #expect(fields.first?.data.count == 12)
    }

    @Test func rejectsFileWithoutTES4() {
        #expect(throws: ESMError.missingTES4) {
            _ = try ESMFile(data: ESMFixture.topGroup("GMST", contents: Data()))
        }
        #expect(throws: ESMError.missingTES4) {
            _ = try ESMFile(data: Data())
        }
    }

    @Test func walksTopGroups() throws {
        let gmst = ESMFixture.record(
            "GMST",
            formID: 0x123,
            data: ESMFixture.field("EDID", Data("fTest\0".utf8))
        )
        let data = ESMFixture.tes4()
            + ESMFixture.topGroup("GMST", contents: gmst)
            + ESMFixture.topGroup("KYWD", contents: Data())
        let file = try ESMFile(data: data)
        #expect(file.topGroups.count == 2)
        #expect(file.topGroup(of: "KYWD") != nil)
        #expect(file.topGroup(of: "WRLD") == nil)

        let group = try #require(file.topGroup(of: "GMST"))
        #expect(group.kind == .top)
        let children = try group.children()
        #expect(children.count == 1)
        guard case let .record(record)? = children.first else {
            Issue.record("expected a record child")
            return
        }
        #expect(record.type == "GMST")
        #expect(record.formID == 0x123)
        #expect(try record.fields().first?.type == "EDID")
    }

    /// WRLD top group -> WRLD record + world children -> exterior block ->
    /// sub-block -> CELL record + cell children -> temporary children -> REFR.
    @Test func walksNestedWorldspaceGroups() throws {
        let refr = ESMFixture.record("REFR", formID: 0x3C, data: Data())
        let temporary = ESMFixture.childGroup(parent: 0x2B, groupType: 9, contents: refr)
        let cell = ESMFixture.record("CELL", formID: 0x2B, data: Data())
        let cellChildren = ESMFixture.childGroup(parent: 0x2B, groupType: 6, contents: temporary)
        let subBlock = ESMFixture.exteriorBlock(
            x: -1, y: 2, groupType: 5, contents: cell + cellChildren
        )
        let block = ESMFixture.exteriorBlock(x: -1, y: 2, groupType: 4, contents: subBlock)
        let worldChildren = ESMFixture.childGroup(parent: 0x1A, groupType: 1, contents: block)
        let wrld = ESMFixture.record("WRLD", formID: 0x1A, data: Data())
        let data = ESMFixture.tes4() + ESMFixture.topGroup("WRLD", contents: wrld + worldChildren)

        let file = try ESMFile(data: data)
        let top = try #require(file.topGroup(of: "WRLD"))
        let topChildren = try top.children()
        #expect(topChildren.count == 2)

        guard case let .group(children)? = topChildren.last else {
            Issue.record("expected world children group")
            return
        }
        #expect(children.kind == .worldChildren)
        #expect(children.parentFormID == 0x1A)

        guard case let .group(blockGroup)? = try children.children().first else {
            Issue.record("expected exterior block group")
            return
        }
        #expect(blockGroup.kind == .exteriorCellBlock)
        #expect(blockGroup.grid?.x == -1)
        #expect(blockGroup.grid?.y == 2)

        guard case let .group(subBlockGroup)? = try blockGroup.children().first else {
            Issue.record("expected exterior sub-block group")
            return
        }
        let cellLevel = try subBlockGroup.children()
        #expect(cellLevel.count == 2)
        guard
            case let .record(cellRecord)? = cellLevel.first,
            case let .group(cellGroup)? = cellLevel.last
        else {
            Issue.record("expected CELL record + cell children group")
            return
        }
        #expect(cellRecord.type == "CELL")
        #expect(cellGroup.kind == .cellChildren)
        #expect(cellGroup.parentFormID == 0x2B)

        guard
            case let .group(temporaryGroup)? = try cellGroup.children().first,
            case let .record(refrRecord)? = try temporaryGroup.children().first
        else {
            Issue.record("expected temporary children group with REFR")
            return
        }
        #expect(temporaryGroup.kind == .cellTemporaryChildren)
        #expect(refrRecord.type == "REFR")
        #expect(refrRecord.formID == 0x3C)
    }

    @Test func decompressesCompressedRecord() throws {
        let fieldData = ESMFixture.field("MODL", Data("meshes\\clutter\\test01.nif\0".utf8))
        let stat = ESMFixture.compressedRecord("STAT", formID: 7, fieldData: fieldData)
        let data = ESMFixture.tes4() + ESMFixture.topGroup("STAT", contents: stat)

        let file = try ESMFile(data: data)
        let group = try #require(file.topGroup(of: "STAT"))
        guard case let .record(record)? = try group.children().first else {
            Issue.record("expected STAT record")
            return
        }
        #expect(record.isCompressed)
        let fields = try record.fields()
        #expect(fields.count == 1)
        #expect(fields.first?.type == "MODL")
        #expect(fields.first?.data == Data("meshes\\clutter\\test01.nif\0".utf8))
    }

    @Test func resolvesXXXXSizeExtension() throws {
        let big = Data(repeating: 0xAB, count: 70000) // over uint16 max
        let payload = ESMFixture.field("EDID", Data("nav\0".utf8))
            + ESMFixture.longField("NVNM", big)
        let record = ESMFixture.record("NAVM", formID: 9, data: payload)
        let file = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "NAVM", contents: record
        ))

        guard case let .record(navm)? = try #require(file.topGroup(of: "NAVM")).children().first
        else {
            Issue.record("expected NAVM record")
            return
        }
        let fields = try navm.fields()
        #expect(fields.map(\.type) == ["EDID", "NVNM"])
        #expect(fields.last?.data == big)
    }

    @Test func throwsOnTruncatedRecordData() throws {
        // Record claims 4 bytes of data but the group ends after 2.
        let truncated = ESMFixture.record("GMST", data: Data([1, 2, 3, 4])).dropLast(2)
        let file = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "GMST", contents: Data(truncated)
        ))
        let group = try #require(file.topGroup(of: "GMST"))
        #expect(throws: ESMError.self) { _ = try group.children() }
    }

    @Test func throwsOnGroupSizeOutOfBounds() {
        let group = ESMFixture.topGroup("GMST", contents: Data(count: 8))
        #expect(throws: ESMError.self) {
            _ = try ESMFile(data: ESMFixture.tes4() + group.dropLast(4))
        }
    }

    @Test func throwsOnFieldSizePastRecordEnd() throws {
        // Field claims 200 bytes; record data holds 6.
        var payload = Data("EDID".utf8)
        payload.appendUInt16(200)
        let record = ESMFixture.record("GMST", data: payload)
        let file = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "GMST", contents: record
        ))
        guard case let .record(gmst)? = try #require(file.topGroup(of: "GMST")).children().first
        else {
            Issue.record("expected GMST record")
            return
        }
        #expect(throws: BinaryReaderError.self) { _ = try gmst.fields() }
    }
}
