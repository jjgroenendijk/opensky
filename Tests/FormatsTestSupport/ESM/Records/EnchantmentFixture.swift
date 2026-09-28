// Record builder shared by the enchantment record tests, the store tests, and the runtime
// tests that build stores from the same records. Every byte is built in code.

import Foundation
@testable import OpenSkyFormats

public enum EnchantmentFixture: Sendable {
    /// The ENIT struct: cost, flags, cast type, amount, delivery, enchantment
    /// type, charge time, base enchantment, worn restrictions. Passing nil for
    /// `wornRestrictions` produces the 32-byte variant that omits it.
    public static func enit(
        cost: Int32 = 0,
        flags: UInt32 = 0,
        castingType: UInt32 = 1,
        amount: Int32 = 0,
        delivery: UInt32 = 1,
        type: UInt32 = 6,
        chargeTime: Float = 0.5,
        baseEnchantment: UInt32 = 0,
        wornRestrictions: UInt32? = 0
    ) -> Data {
        var words: [UInt32] = [
            UInt32(bitPattern: cost),
            flags,
            castingType,
            UInt32(bitPattern: amount),
            delivery,
            type,
            chargeTime.bitPattern,
            baseEnchantment
        ]
        if let wornRestrictions {
            words.append(wornRestrictions)
        }
        return MagicEffectFixture.words(words)
    }

    /// One ENCH plus a weapon and a piece of armor that both name it, for the
    /// suites that exercise the EITM links.
    public static func itemPlugin() throws -> ESMFile {
        let weapon = ESMFixture.record(
            "WEAP",
            formID: 0x500,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestEnchantedBlade"))
                + InventoryFixture.formIDField("EITM", 0x42)
                + ESMFixture.field("EAMT", chargeField(1500))
                + ESMFixture.field("DATA", InventoryFixture.weaponData(
                    value: 100,
                    weight: 12,
                    damage: 9
                ))
        )
        let plainWeapon = ESMFixture.record(
            "WEAP",
            formID: 0x600,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestPlainBlade"))
                + ESMFixture.field("DATA", InventoryFixture.weaponData(
                    value: 25,
                    weight: 9,
                    damage: 7
                ))
        )
        let armor = ESMFixture.record(
            "ARMO",
            formID: 0x700,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestEnchantedCuirass"))
                + InventoryFixture.formIDField("EITM", 0x42)
                + ESMFixture.field("DATA", InventoryFixture.valueWeightData(
                    value: 125,
                    weight: 30
                ))
        )
        return try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords + [
                record(
                    formID: 0x42,
                    editorID: "TestEnchFire",
                    name: "Burning",
                    enit: enit(cost: 60, amount: 1500),
                    effects: [.init(0x50, magnitude: 25)]
                ),
                weapon,
                plainWeapon,
                armor
            ]
        )
    }

    /// EAMT, the weapon-side charge: a bare uint16.
    public static func chargeField(_ value: UInt16) -> Data {
        var data = Data()
        data.appendUInt16(value)
        return data
    }

    public static func record(
        formID: UInt32,
        editorID: String,
        name: String,
        enit: Data,
        effects: [SpellStoreFixture.EffectSpec] = []
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("FULL", ESMFixture.zstring(name))
        fields += ESMFixture.field("ENIT", enit)
        for effect in effects {
            fields += InventoryFixture.effectFields(
                effect: effect.effect,
                magnitude: effect.magnitude,
                area: 0,
                duration: effect.duration
            )
        }
        return ESMFixture.record("ENCH", formID: formID, data: fields)
    }
}
