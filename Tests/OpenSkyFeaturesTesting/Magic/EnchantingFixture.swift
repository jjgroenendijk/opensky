// Records for the enchanting suites: two effects that power changes, a weapon base and
// two apparel bases, one enchanted sword whose ENCH links the weapon base, a plain
// sword, a plain ring, and the soul gems. Every byte is built here.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting

public enum EnchantingFixture {
    public static let fireBase = FormID(0x70)
    public static let fireStrong = FormID(0x71)
    public static let healthBase = FormID(0x72)
    public static let magickaBase = FormID(0x73)

    public static let fireSword = FormID(0x0000_0800)
    public static let ironSword = FormID(0x0000_0801)
    public static let ring = FormID(0x0000_0802)

    /// The weapon base's manual cost per use.
    public static let fireBaseCost: Float = 100

    public static func plugin() throws -> ESMFile {
        try SpellStoreFixture.plugin(
            records: effects + bases + items + SoulGemFixture.gemRecords
        )
    }

    private static var effects: [Data] {
        [
            effect(
                0x60,
                "EnchFireDamage",
                flags: [.hostile, .powerAffectsMagnitude],
                cast: 1,
                delivery: 1
            ),
            effect(
                0x61,
                "EnchFortifyHealth",
                flags: [.recover, .powerAffectsMagnitude],
                cast: 0,
                delivery: 0
            )
        ]
    }

    private static var bases: [Data] {
        let manual = EnchantmentFlags.manualCostCalc.rawValue
        return [
            EnchantmentFixture.record(
                formID: fireBase.rawValue, editorID: "EnchWeaponFireBase", name: "Fire Damage",
                enit: EnchantmentFixture.enit(cost: Int32(fireBaseCost), flags: manual),
                effects: [.init(0x60, magnitude: 10)]
            ),
            EnchantmentFixture.record(
                formID: fireStrong.rawValue, editorID: "EnchWeaponFire02", name: "Burning",
                enit: EnchantmentFixture.enit(
                    cost: 30, flags: manual, amount: 1000, baseEnchantment: fireBase.rawValue
                ),
                effects: [.init(0x60, magnitude: 20)]
            ),
            apparelBase(healthBase, "EnchArmorFortifyHealthBase", "Fortify Health", magnitude: 30),
            apparelBase(
                magickaBase,
                "EnchArmorFortifyMagickaBase",
                "Fortify Magicka",
                magnitude: 20
            )
        ]
    }

    private static var items: [Data] {
        [
            ESMFixture.record(
                "WEAP", formID: fireSword.rawValue,
                data: ESMFixture.field("EDID", ESMFixture.zstring("TestFireSword"))
                    + InventoryFixture.formIDField("EITM", fireStrong.rawValue)
                    + ESMFixture.field("EAMT", EnchantmentFixture.chargeField(1000))
                    + ESMFixture.field("DATA", InventoryFixture.weaponData(
                        value: 100, weight: 9, damage: 7
                    ))
            ),
            ESMFixture.record(
                "WEAP", formID: ironSword.rawValue,
                data: ESMFixture.field("EDID", ESMFixture.zstring("TestIronSword"))
                    + ESMFixture.field("DATA", InventoryFixture.weaponData(
                        value: 25, weight: 9, damage: 7
                    ))
            ),
            ESMFixture.record(
                "ARMO", formID: ring.rawValue,
                data: ESMFixture.field("EDID", ESMFixture.zstring("TestRing"))
                    + ESMFixture.field("DATA", InventoryFixture.valueWeightData(
                        value: 50, weight: 0.25
                    ))
            )
        ]
    }

    private static func apparelBase(
        _ id: FormID, _ editorID: String, _ name: String, magnitude: Float
    ) -> Data {
        EnchantmentFixture.record(
            formID: id.rawValue, editorID: editorID, name: name,
            enit: EnchantmentFixture.enit(
                flags: EnchantmentFlags.manualCostCalc.rawValue, castingType: 0, delivery: 0
            ),
            effects: [.init(0x61, magnitude: magnitude)]
        )
    }

    private static func effect(
        _ id: UInt32, _ editorID: String, flags: MagicEffectFlags, cast: UInt32, delivery: UInt32
    ) -> Data {
        ESMFixture.record(
            "MGEF", formID: id,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("FULL", ESMFixture.zstring(editorID))
                + ESMFixture.field("DATA", MagicEffectFixture.data(
                    castingType: cast, delivery: delivery, baseCost: 1, flags: flags
                ))
        )
    }
}
