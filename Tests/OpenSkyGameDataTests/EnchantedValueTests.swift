// An enchanted weapon or armour is worth its record value plus the enchantment
// (UESP "Skyrim Mod:Mod File Format/WEAP" and ".../ARMO").

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct EnchantedValueTests {
    /// A manual-cost enchantment of cost 60 and charge 1500 on a 100-gold sword and a
    /// 125-gold cuirass.
    private func store() throws -> ItemDefinitionStore {
        let enchantment = EnchantmentFixture.record(
            formID: 0x42, editorID: "TestEnchFire", name: "Burning",
            enit: EnchantmentFixture.enit(cost: 60, flags: 1, amount: 1500),
            effects: [.init(0x50, magnitude: 25)]
        )
        let weapon = ESMFixture.record(
            "WEAP", formID: 0x500,
            data: InventoryFixture.formIDField("EITM", 0x42)
                + ESMFixture.field("EAMT", EnchantmentFixture.chargeField(1500))
                + ESMFixture.field(
                    "DATA", InventoryFixture.weaponData(value: 100, weight: 12, damage: 9)
                )
        )
        let armour = ESMFixture.record(
            "ARMO", formID: 0x700,
            data: InventoryFixture.formIDField("EITM", 0x42)
                + ESMFixture.field(
                    "DATA", InventoryFixture.valueWeightData(value: 125, weight: 30)
                )
        )
        let file = try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords + [enchantment, weapon, armour]
        )
        let index = RecordIndex(plugins: [("Base.esm", file)], recordTypes: ["MGEF", "ENCH"])
        return ItemDefinitionStore(
            file: file,
            enchantments: ItemEnchantmentResolver(
                store: EnchantmentStore(index: index), pluginName: "Base.esm"
            )
        )
    }

    @Test func aWeaponAddsItsChargeAndCost() throws {
        let store = try store()
        // 100 + floor(0.12 * 1500 + 8 * 60) = 100 + 660.
        #expect(store.gameValue(of: FormID(0x500)) == 760)
    }

    @Test func anArmourAddsItsCost() throws {
        let store = try store()
        // 125 + floor(60 + 0.5).
        #expect(store.gameValue(of: FormID(0x700)) == 185)
    }

    @Test func theSettingsScaleTheWeaponTerms() throws {
        let store = try store()
        var settings = EnchantedValueSettings.vanilla
        settings.chargeMult = 0
        settings.costMult = 1
        store.enchantedValueSettings = settings
        #expect(store.gameValue(of: FormID(0x500)) == 160)
        #expect(store.gameValue(of: FormID(0x999)) == 0)
    }
}
