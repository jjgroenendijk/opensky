// KEYM, SLGM, and APPA over synthetic InventoryFixture records.
// Layout: docs/formats/item-records.md.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct MinorItemRecordTests {
    private static func record(_ type: String, flags: UInt32 = 0, _ fields: Data) throws
        -> ESMRecord
    {
        try InventoryFixture.record(
            ESMFixture.record(type, formID: 0x42, flags: flags, data: fields)
        )
    }

    private static func valueWeight(_ value: Int32, _ weight: Float) -> Data {
        ESMFixture.field("DATA", InventoryFixture.valueWeightData(value: value, weight: weight))
    }

    @Test func decodesKey() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("WhiterunJailKey"))
        fields += ESMFixture.field("VMAD", Data(count: 6))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Jail Key"))
        fields += ESMFixture.field("MODL", ESMFixture.zstring("clutter\\key01.nif"))
        fields += InventoryFixture.keywordFields([0x0009_14EF])
        fields += Self.valueWeight(0, 0)
        let key = try KeyItem(record: Self.record("KEYM", fields), localized: false)
        #expect(key.formID == FormID(0x42))
        #expect(key.fields.editorID == "WhiterunJailKey")
        #expect(key.fields.name == .inline("Jail Key"))
        #expect(key.fields.keywords.keywords == [FormID(0x0009_14EF)])
        #expect(key.itemValue == .zero)
        #expect(key.isPlayable)
        #expect(key.skipped.counts == [.unknownField("VMAD"): 1])
    }

    @Test func keyHeaderFlagMarksNonPlayable() throws {
        let key = try KeyItem(record: Self.record("KEYM", flags: 0x04, Data()), localized: false)
        #expect(!key.isPlayable)
    }

    @Test func decodesSoulGem() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("SoulGemBlackFilled"))
        fields += Self.valueWeight(1000, 1)
        fields += ESMFixture.field("SOUL", Data([5]))
        fields += ESMFixture.field("SLCP", Data([5]))
        fields += InventoryFixture.formIDField("NAM0", 0x0002_E500)
        let gem = try SoulGem(
            record: Self.record("SLGM", flags: 0x0002_0000, fields),
            localized: false
        )
        #expect(gem.fields.editorID == "SoulGemBlackFilled")
        #expect(gem.itemValue == ItemValue(value: 1000, weight: 1))
        #expect(gem.containedSoul == .grand)
        #expect(gem.capacity == .grand)
        #expect(gem.linkedGem == FormID(0x0002_E500))
        #expect(gem.canHoldNPCSoul)
        #expect(gem.skipped.isEmpty)
    }

    /// A truncated field costs only itself: the rest of the record still decodes.
    @Test func soulGemSurvivesTruncatedFields() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("SoulGemPetty"))
        fields += ESMFixture.field("DATA", Data(count: 4))
        fields += ESMFixture.field("SOUL", Data())
        fields += ESMFixture.field("SLCP", Data([1]))
        let gem = try SoulGem(record: Self.record("SLGM", fields), localized: false)
        #expect(gem.fields.editorID == "SoulGemPetty")
        #expect(gem.itemValue == .zero)
        #expect(gem.containedSoul == nil)
        #expect(gem.capacity == .petty)
        #expect(!gem.canHoldNPCSoul)
        #expect(gem.skipped.counts == [.malformedField("DATA"): 1, .malformedField("SOUL"): 1])
    }

    @Test(arguments: UInt8(0) ... 7)
    func soulLevelRoundTrips(raw: UInt8) {
        let level = SoulLevel(rawValue: raw)
        #expect(level.rawValue == raw)
        #expect((level == .unknown(raw)) == (raw > 5))
    }

    @Test func decodesApparatus() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("MortarPestle01"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Mortar and Pestle"))
        var quality = Data()
        quality.appendUInt32(3)
        fields += ESMFixture.field("QUAL", quality)
        fields += ESMFixture.field("DESC", ESMFixture.zstring("Grinds things."))
        fields += Self.valueWeight(15, 2)
        let apparatus = try Apparatus(record: Self.record("APPA", fields), localized: false)
        #expect(apparatus.fields.editorID == "MortarPestle01")
        #expect(apparatus.quality == .expert)
        #expect(apparatus.description == .inline("Grinds things."))
        #expect(apparatus.itemValue == ItemValue(value: 15, weight: 2))
        #expect(apparatus.skipped.isEmpty)
    }

    @Test(arguments: Int32(-1) ... 6)
    func apparatusQualityRoundTrips(raw: Int32) {
        let quality = ApparatusQuality(rawValue: raw)
        #expect(quality.rawValue == raw)
        #expect((quality == .unknown(raw)) == !(0 ... 4).contains(raw))
    }

    @Test func rejectsWrongRecordTypes() throws {
        let misc = try Self.record("MISC", Data())
        #expect(throws: ESMError.self) { _ = try KeyItem(record: misc, localized: false) }
        #expect(throws: ESMError.self) { _ = try SoulGem(record: misc, localized: false) }
        #expect(throws: ESMError.self) { _ = try Apparatus(record: misc, localized: false) }
    }
}
