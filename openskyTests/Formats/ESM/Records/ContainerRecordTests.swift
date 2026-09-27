// CONT contents (COCT/CNTO/COED) and REFR reference-level ownership
// (XOWN/XRNK/XCNT). Fixtures are synthetic in-code records
// (InventoryFixture) — never extracted game files (AGENTS.md "Legal & IP
// boundary").
//
// Layouts: UESP "Skyrim Mod:Mod File Format" subpages /CONT and /REFR,
// cross-checked against xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas and
// Core/wbDefinitionsCommon.pas `wbOwnership`. See docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

struct ContainerRecordTests {
    /// Container composes ModelBase rather than replacing it, so the fields
    /// the cell builder and interaction path already read must still decode.
    @Test func decodesContentsAndKeepsModelBaseDecode() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("ChestSmall"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Chest"))
        fields += ESMFixture.field("MODL", ESMFixture.zstring("clutter\\chest.nif"))
        var count = Data()
        count.appendUInt32(2)
        fields += ESMFixture.field("COCT", count)
        fields += ESMFixture.field("CNTO", InventoryFixture.cntoData(item: 0x0AA, count: 3))
        fields += ESMFixture.field("CNTO", InventoryFixture.cntoData(item: 0x0BB, count: 1))
        fields += ESMFixture.field(
            "COED", InventoryFixture.coedData(owner: 0x0CC, condition: 0.5)
        )
        var flags = Data([0x02])
        flags.appendUInt32(0)
        fields += ESMFixture.field("DATA", flags)
        fields += InventoryFixture.formIDField("SNAM", 0x0DD)
        let container = try Container(
            record: InventoryFixture.record(
                ESMFixture.record("CONT", formID: 0x77, data: fields)
            ),
            localized: false
        )
        #expect(container.formID == FormID(0x77))
        #expect(container.base.editorID == "ChestSmall")
        #expect(container.base.modelPath == "clutter\\chest.nif")
        #expect(container.base.sounds?.activation == FormID(0x0DD))
        #expect(container.entries.count == 2)
        #expect(container.entries[0] == Container.Entry(
            item: FormID(0x0AA), count: 3, owner: nil, ownerCondition: nil, condition: nil
        ))
        // COED attaches to the CNTO immediately before it, not the first.
        #expect(container.entries[1].owner == FormID(0x0CC))
        #expect(container.entries[1].condition == 0.5)
        #expect(container.declaredEntryCount == 2)
        #expect(!container.entryCountMismatch)
        #expect(container.flags == [.respawns])
    }

    @Test func countMismatchIsReportedNotEnforced() throws {
        var count = Data()
        count.appendUInt32(5)
        var fields = ESMFixture.field("COCT", count)
        fields += ESMFixture.field("CNTO", InventoryFixture.cntoData(item: 0x01, count: 1))
        let container = try Container(
            record: InventoryFixture.record(ESMFixture.record("CONT", data: fields)),
            localized: false
        )
        #expect(container.entries.count == 1)
        #expect(container.entryCountMismatch)
    }

    @Test func dropsShortEntriesAndOrphanExtraData() throws {
        var fields = ESMFixture.field(
            "COED", InventoryFixture.coedData(owner: 0x01, condition: 1)
        )
        fields += ESMFixture.field("CNTO", Data(count: 7))
        let container = try Container(
            record: InventoryFixture.record(ESMFixture.record("CONT", data: fields)),
            localized: false
        )
        #expect(container.entries.isEmpty)
    }

    @Test func rejectsWrongRecordType() {
        #expect(throws: ESMError.self) {
            _ = try Container(
                record: InventoryFixture.record(ESMFixture.record("MISC", data: Data())),
                localized: false
            )
        }
    }

    @Test func emptyRecordDecodesToDefaults() throws {
        let container = try Container(
            record: InventoryFixture.record(ESMFixture.record("CONT", data: Data())),
            localized: false
        )
        #expect(container.entries.isEmpty)
        #expect(container.declaredEntryCount == nil)
        #expect(container.flags.isEmpty)
    }
}

struct PlacedReferenceOwnershipTests {
    @Test func decodesOwnershipAndCount() throws {
        var fields = InventoryFixture.formIDField("NAME", 0x0AA)
        fields += ESMFixture.field("DATA", Data(count: 24))
        fields += InventoryFixture.formIDField("XOWN", 0x0001_3480)
        var rank = Data()
        rank.appendUInt32(UInt32(bitPattern: Int32(2)))
        fields += ESMFixture.field("XRNK", rank)
        var itemCount = Data()
        itemCount.appendUInt32(UInt32(bitPattern: Int32(25)))
        fields += ESMFixture.field("XCNT", itemCount)
        let reference = try PlacedReference(
            record: InventoryFixture.record(
                ESMFixture.record("REFR", formID: 0x99, data: fields)
            )
        )
        #expect(reference.owner == FormID(0x0001_3480))
        #expect(reference.ownerFactionRank == 2)
        #expect(reference.itemCount == 25)
    }

    @Test func absentOwnershipLeavesFieldsNil() throws {
        var fields = InventoryFixture.formIDField("NAME", 0x0AA)
        fields += ESMFixture.field("DATA", Data(count: 24))
        // A null XOWN is "unowned", not "owned by FormID 0".
        fields += InventoryFixture.formIDField("XOWN", 0)
        let reference = try PlacedReference(
            record: InventoryFixture.record(ESMFixture.record("REFR", data: fields))
        )
        #expect(reference.owner == nil)
        #expect(reference.ownerFactionRank == nil)
        #expect(reference.itemCount == nil)
    }
}
