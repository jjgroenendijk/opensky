@testable import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

/// Load order `Base.esm`, `Other.esm`, `Mod.esp`. `Mod.esp` lists only `Base.esm`,
/// so its own records are `01xxxxxx` in the file and `02xxxxxx` in the load order.
@Suite(.tags(.parser))
struct LoadOrderRecordIndexTests {
    private static let cell: UInt32 = 0x0000_0100
    private static let overridden: UInt32 = 0x0000_0200
    private static let removed: UInt32 = 0x0000_0201

    private func reference(
        _ formID: UInt32,
        base: UInt32 = 0x10,
        x: Float = 0,
        flags: UInt32 = 0,
        extra: Data = Data()
    ) -> Data {
        var placement = Data()
        for value in [x, 0, 0, 0, 0, 0] as [Float] {
            placement.appendFloat32(value)
        }
        let fields = ESMFixture.field("NAME", ESMFixture.words([base]))
            + extra + ESMFixture.field("DATA", placement)
        return ESMFixture.record("REFR", formID: formID, flags: flags, data: fields)
    }

    private func interiorCell(_ formID: UInt32, children: Data) -> Data {
        var cellData = Data()
        cellData.appendUInt16(0x0001) // interior
        let cell = ESMFixture.record(
            "CELL", formID: formID, data: ESMFixture.field("DATA", cellData)
        )
        var label = Data()
        label.appendUInt32(formID)
        let temporary = ESMFixture.group(label: label, groupType: 9, contents: children)
        let block = ESMFixture.group(
            label: Data([0, 0, 0, 0]), groupType: 2,
            contents: ESMFixture.group(
                label: Data([0, 0, 0, 0]), groupType: 3,
                contents: cell + ESMFixture.group(label: label, groupType: 6, contents: temporary)
            )
        )
        return ESMFixture.topGroup("CELL", contents: block)
    }

    private func index() throws -> LoadOrderRecordIndex {
        let base = try ESMFile(data: ESMFixture.tes4() + interiorCell(
            Self.cell,
            children: reference(Self.overridden) + reference(Self.removed)
        ))
        let other = try ESMFile(data: ESMFixture.tes4(masters: ["Base.esm"]))
        let parent = ESMFixture.field("XESP", ESMFixture.words([0x0100_0801]) + Data([0]))
        let mod = try ESMFile(data: ESMFixture.tes4(masters: ["Base.esm"]) + interiorCell(
            Self.cell,
            children: reference(Self.overridden, x: 64)
                + reference(Self.removed, flags: 0x20)
                + reference(0x0100_0800, base: 0x0100_0900, extra: parent)
        ))
        return LoadOrderRecordIndex(
            plugins: [("Base.esm", base), ("Other.esm", other), ("Mod.esp", mod)]
        )
    }

    @Test func aPluginThatListsItsMastersInLoadOrderKeepsItsFormIDs() throws {
        let index = try index()
        #expect(index.plugins.map(\.translation.isIdentity) == [true, true, false])
    }

    @Test func theLastPluginWinsAndIsRenumbered() throws {
        let index = try index()
        let found = try #require(index.record(withFormID: FormID(Self.overridden)))
        #expect(found.position == 2)
        #expect(try found.decode(PlacedReference.init(record:)).placement.position.x == 64)
        #expect(index.record(withFormID: FormID(0x0200_0800))?.position == 2)
        #expect(index.record(withFormID: FormID(0x0100_0800)) == nil)
    }

    @Test func aLaterPluginAddsReferencesToAMasterCell() throws {
        let index = try index()
        let children = index.laterChildren(ofCell: FormID(Self.cell))
        #expect(children.map(\.record.formID.rawValue) == [
            Self.overridden,
            Self.removed,
            0x0200_0800
        ])
        #expect(children.map(\.record.record.isDeleted) == [false, true, false])
        let added = try children[2].record.decode(PlacedReference.init(record:))
        #expect(added.base == FormID(0x0200_0900))
        #expect(added.enableParent?.parent == FormID(0x0200_0801))
        #expect(index.cellFormID(containing: FormID(0x0200_0800)) == FormID(Self.cell))
    }

    @Test func theFirstPluginGetsNoChildrenTable() throws {
        let base = try ESMFile(data: ESMFixture.tes4() + interiorCell(
            Self.cell, children: reference(Self.overridden)
        ))
        let index = LoadOrderRecordIndex(plugins: [("Base.esm", base)])
        #expect(index.laterChildren(ofCell: FormID(Self.cell)).isEmpty)
        #expect(index.cellFormID(containing: FormID(Self.overridden)) == FormID(Self.cell))
    }

    @Test func outsideTheDecodeScopeFormIDsStayAsWritten() throws {
        let index = try index()
        let child = try #require(index.laterChildren(ofCell: FormID(Self.cell)).last)
        let raw = try PlacedReference(record: child.record.record)
        #expect(raw.base == FormID(0x0100_0900))
        #expect(child.record.formID == FormID(0x0200_0800))
    }

    @Test func aLaterPluginsTableIDsNameThePlugin() throws {
        let index = try index()
        let field = ESMField(type: "FULL", data: ESMFixture.words([7]))
        let mod = index.plugins[2]
        #expect(try mod.decode { try LString(field: field, localized: true) }
            == .pluginTableID(7, plugin: "Mod.esp"))
        #expect(try index.plugins[0].decode { try LString(field: field, localized: true) }
            == .tableID(7))
    }

    @Test func aStoreSeesEveryPluginAndTheLastWins() throws {
        func keyword(_ formID: UInt32, _ name: String) -> Data {
            ESMFixture.record("KYWD", formID: formID, data: ESMFixture.field(
                "EDID", Data(name.utf8) + Data([0])
            ))
        }
        let base = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "KYWD", contents: keyword(0x10, "Old") + keyword(0x11, "Kept")
        ))
        let other = try ESMFile(data: ESMFixture.tes4(masters: ["Base.esm"]))
        let mod = try ESMFile(data: ESMFixture.tes4(masters: ["Base.esm"]) + ESMFixture.topGroup(
            "KYWD", contents: keyword(0x10, "New") + keyword(0x0100_0020, "Added")
        ))
        let loadOrder = LoadOrderPlugins(
            [("Base.esm", base), ("Other.esm", other), ("Mod.esp", mod)]
        )
        var skipped = SkippedRecords()
        let names = loadOrder.indexRecords(of: "KYWD", skipped: &skipped) {
            ESMWalk.editorID(of: $0)
        }
        #expect(names == [0x10: "New", 0x11: "Kept", 0x0200_0020: "Added"])
        let ids = loadOrder.decodeRecords(of: "KYWD", skipped: &skipped) { FormID($0.formID) }
        #expect(ids == [FormID(0x10), FormID(0x11), FormID(0x0200_0020)])
        #expect(skipped.isEmpty)
    }
}
