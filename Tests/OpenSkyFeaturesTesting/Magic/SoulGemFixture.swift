// The inventory fixture plugin plus five SLGM records: three white gems, a black gem,
// and the two filled records the grand and black gems link to. Every byte is built here.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyInventoryInterface

public enum SoulGemFixture {
    public static let petty = FormID(0x0000_8000)
    public static let common = FormID(0x0000_8010)
    /// Links `grandFilled`, as vanilla's empty grand gem does.
    public static let grand = FormID(0x0000_8020)
    public static let grandFilled = FormID(0x0000_8021)
    /// Can hold NPC souls; links `blackFilled`.
    public static let black = FormID(0x0000_8030)
    public static let blackFilled = FormID(0x0000_8031)

    private static let canHoldNPCSoul: UInt32 = 0x0002_0000

    public static func pluginBytes() -> Data {
        let records = gem(petty, "SoulGemPetty", capacity: 1)
            + gem(common, "SoulGemCommon", capacity: 3)
            + gem(grand, "SoulGemGrand", capacity: 5, linked: grandFilled)
            + gem(grandFilled, "SoulGemGrandFilled", capacity: 5, soul: 5)
            + gem(black, "SoulGemBlack", flags: canHoldNPCSoul, linked: blackFilled)
            + gem(blackFilled, "SoulGemBlackFilled", flags: canHoldNPCSoul, soul: 5)
        return InventoryBaselineFixture.pluginBytes() + ESMFixture.topGroup(
            "SLGM",
            contents: records
        )
    }

    public static func resolver() throws -> InventoryBaselineResolver {
        try InventoryBaselineResolver.build(from: ESMFile(data: pluginBytes()))
    }

    private static func gem(
        _ id: FormID, _ editorID: String, flags: UInt32 = 0,
        capacity: UInt8? = nil, soul: UInt8 = 0, linked: FormID? = nil
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("DATA", InventoryFixture.valueWeightData(value: 10, weight: 0.1))
        fields += ESMFixture.field("SOUL", Data([soul]))
        if let capacity {
            fields += ESMFixture.field("SLCP", Data([capacity]))
        }
        if let linked {
            fields += InventoryFixture.formIDField("NAM0", linked.rawValue)
        }
        return ESMFixture.record("SLGM", formID: id.rawValue, flags: flags, data: fields)
    }
}
