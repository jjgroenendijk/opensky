// The skip tallies of the record decoders that walk fields in a loop, and the
// xEdit-named fields they read. Synthetic records only.
// Layout: docs/formats/records.md.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct UnreadFieldTallyTests {
    private static func record(_ type: String, _ fields: Data) throws -> ESMRecord {
        try ESMFixture.parseRecord(ESMFixture.record(type, formID: 0x42, data: fields))
    }

    private static func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }

    private static func valueWeight() -> Data {
        var data = Data()
        data.appendUInt32(5)
        data.appendFloat32(1)
        return data
    }

    @Test func aFieldNoDecoderReadsIsCountedOnce() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("Thing"))
        fields += ESMFixture.field("DATA", Self.valueWeight())
        fields += ESMFixture.field("XYZW", Data(count: 3))
        fields += ESMFixture.field("XYZW", Data(count: 3))
        let item = try MiscItem(record: Self.record("MISC", fields), localized: false)
        #expect(item.skipped.counts == [.unknownField("XYZW"): 2])
    }

    @Test func itemScriptsAreReadNotTallied() throws {
        var vmad = Data()
        vmad.appendUInt16(5)
        vmad.appendUInt16(2)
        vmad.appendUInt16(0)
        var fields = ESMFixture.field("VMAD", vmad)
        fields += ESMFixture.field("DATA", Self.valueWeight())
        let item = try MiscItem(record: Self.record("MISC", fields), localized: false)
        #expect(item.skipped.isEmpty)
        #expect(item.fields.scriptData.version == 5)
    }

    @Test func armorReadsItsDetails() throws {
        var fields = ESMFixture.field("OBND", Data(count: 12))
        fields += ESMFixture.field("MOD2", ESMFixture.zstring("armor\\m.nif"))
        fields += ESMFixture.field("MO2T", Data(count: 12))
        fields += ESMFixture.field("MOD4", ESMFixture.zstring("armor\\f.nif"))
        fields += ESMFixture.field("DATA", Self.valueWeight())
        fields += ESMFixture.field("TNAM", Self.uint32(0x77))
        fields += ESMFixture.field("BAMT", Self.uint32(0x78))
        fields += ESMFixture.field("DESC", ESMFixture.zstring(""))
        let armor = try Armor(record: Self.record("ARMO", fields), localized: false)
        #expect(armor.skipped.isEmpty)
        #expect(armor.details.maleWorldModel?.path == "armor\\m.nif")
        #expect(armor.details.maleWorldModel?.textureHashes?.count == 12)
        #expect(armor.details.femaleWorldModel?.path == "armor\\f.nif")
        #expect(armor.details.template == FormID(0x77))
        #expect(armor.details.alternateBlockMaterial == FormID(0x78))
        #expect(armor.itemValue.value == 5)
    }

    @Test func armorAddonReadsSkinsAndArt() throws {
        var fields = ESMFixture.field("MOD2", ESMFixture.zstring("m.nif"))
        fields += ESMFixture.field("MO2T", Data(count: 12))
        fields += ESMFixture.field("NAM0", Self.uint32(0x10))
        fields += ESMFixture.field("NAM3", Self.uint32(0x11))
        fields += ESMFixture.field("ONAM", Self.uint32(0x12))
        let addon = try ArmorAddon(record: Self.record("ARMA", fields))
        #expect(addon.skipped.isEmpty)
        #expect(addon.maleModelPath == "m.nif")
        #expect(addon.maleSkinTexture == FormID(0x10))
        #expect(addon.femaleSkinTextureSwapList == FormID(0x11))
        #expect(addon.artObject == FormID(0x12))
    }

    @Test func leveledOwnerDataAttachesToTheEntryBeforeIt() throws {
        var entry = Data()
        entry.appendUInt16(1)
        entry.appendUInt16(0)
        entry.appendUInt32(0x20)
        entry.appendUInt32(1)
        var coed = Data()
        coed.appendUInt32(0x30)
        coed.appendUInt32(2)
        coed.appendFloat32(0.5)
        var fields = ESMFixture.field("LLCT", Data([1]))
        fields += ESMFixture.field("LVLG", Self.uint32(0x40))
        fields += ESMFixture.field("LVLO", entry)
        fields += ESMFixture.field("COED", coed)
        let list = try LeveledList(record: Self.record("LVLI", fields))
        #expect(list.skipped.isEmpty)
        #expect(list.declaredEntryCount == 1)
        #expect(list.chanceNoneGlobal == FormID(0x40))
        #expect(list.entries.first?.owner == FormID(0x30))
        #expect(list.entries.first?.condition == 0.5)
    }

    @Test func containerCountsOnlyWhatNeitherDecoderReads() throws {
        var cnto = Data()
        cnto.appendUInt32(0x50)
        cnto.appendUInt32(3)
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("Chest"))
        fields += ESMFixture.field("CNTO", cnto)
        fields += ESMFixture.field("XYZW", Data(count: 1))
        let chest = try Container(record: Self.record("CONT", fields))
        #expect(chest.entries.count == 1)
        #expect(chest.skipped.counts == [.unknownField("XYZW"): 1])
    }

    @Test func pluginHeaderKeepsOverridesAndCounts() throws {
        var hedr = Data()
        hedr.appendFloat32(1.71)
        hedr.appendUInt32(1)
        hedr.appendUInt32(0x800)
        var fields = ESMFixture.field("HEDR", hedr)
        fields += ESMFixture.field("MAST", ESMFixture.zstring("Skyrim.esm"))
        fields += ESMFixture.field("DATA", Data(count: 8))
        fields += ESMFixture.field("ONAM", Self.uint32(0x60) + Self.uint32(0x61))
        fields += ESMFixture.field("INTV", Self.uint32(9))
        fields += ESMFixture.field("INCC", Self.uint32(4))
        let header = try PluginHeader(tes4: Self.record("TES4", fields))
        #expect(header.skipped.isEmpty)
        #expect(header.masterData == [0])
        #expect(header.overriddenForms == [FormID(0x60), FormID(0x61)])
        #expect(header.interiorCellCount == 4)
    }

    @Test func staticReadsDistantLODSlots() throws {
        var lod = Data()
        for level in 0 ..< 4 {
            var slot = ESMFixture.zstring("lod\\l\(level).nif")
            slot += Data(count: 260 - slot.count)
            lod += slot
        }
        var dnam = Data()
        dnam.appendFloat32(90)
        dnam.appendUInt32(0x70)
        dnam += Data([1, 0, 0, 0])
        var fields = ESMFixture.field("MODL", ESMFixture.zstring("rock.nif"))
        fields += ESMFixture.field("DNAM", dnam)
        fields += ESMFixture.field("MNAM", lod)
        let stat = try StaticObject(record: Self.record("STAT", fields))
        #expect(stat.skipped.isEmpty)
        #expect(stat.modelPath == "rock.nif")
        #expect(stat.distantLODModels == [
            "lod\\l0.nif",
            "lod\\l1.nif",
            "lod\\l2.nif",
            "lod\\l3.nif"
        ])
        #expect(stat.directionalMaterial?.material == FormID(0x70))
        #expect(stat.directionalMaterial?.consideredSnow == true)
    }

    @Test func packageReadsTreeInputsAndEvents() throws {
        var pkcu = Data(count: 12)
        pkcu.replaceSubrange(0 ..< 4, with: Self.uint32(1))
        var prcb = Self.uint32(2)
        prcb += Self.uint32(1)
        let topic = Self.uint32(0) + Self.uint32(0x90)
        var fields = ESMFixture.field("PKDT", Data([0, 0, 0, 0, 19]) + Data(count: 7))
        fields += ESMFixture.field("PSDT", Data(count: 12))
        fields += ESMFixture.field("IDLF", Data([1]))
        fields += ESMFixture.field("IDLA", Self.uint32(0x80))
        fields += ESMFixture.field("QNAM", Self.uint32(0x81))
        fields += ESMFixture.field("PKCU", pkcu)
        fields += ESMFixture.field("XNAM", Data([0]))
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("Procedure"))
        fields += ESMFixture.field("PRCB", prcb)
        fields += ESMFixture.field("PNAM", ESMFixture.zstring("Sit"))
        fields += ESMFixture.field("PKC2", Data([0]))
        fields += ESMFixture.field("UNAM", Data([0]))
        fields += ESMFixture.field("BNAM", ESMFixture.zstring("Target"))
        fields += ESMFixture.field("PNAM", Self.uint32(1))
        for marker in ["POBA", "POEA", "POCA"] {
            fields += ESMFixture.field(marker, Data())
            fields += ESMFixture.field("INAM", Self.uint32(0))
            fields += ESMFixture.field("PDTO", topic)
        }
        let package = try Package(record: Self.record("PACK", fields))
        #expect(package.skipped.isEmpty)
        #expect(package.procedureTypes == ["Sit"])
        #expect(package.details.idleAnimations?.animations == [FormID(0x80)])
        #expect(package.details.ownerQuest == FormID(0x81))
        #expect(package.details.branches.first?.branchCount == 2)
        #expect(package.details.branches.first?.dataInputIndexes == [0])
        #expect(package.details.templateInputs.first?.name == "Target")
        #expect(package.details.templateInputs.first?.isPublic == true)
        #expect(package.details.onChange?.topic?.topic == FormID(0x90))
    }

    @Test func rankedReportMergesSeparateMaps() {
        let ranked = FieldTally.rank([
            ("unknown", ["ABCD": 1] as [FourCC: Int]),
            ("malformed", ["EFGH": 3] as [FourCC: Int])
        ])
        #expect(ranked.map(\.name) == ["malformed EFGH", "unknown ABCD"])
        var tally = FieldTally()
        tally.note(.unknownField("ABCD"), count: 2)
        tally.unnote(.unknownField("ABCD"))
        tally.unnote(.unknownField("ABCD"))
        #expect(tally.isEmpty)
    }
}
