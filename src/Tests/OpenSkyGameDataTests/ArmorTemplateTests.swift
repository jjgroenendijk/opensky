// An ARMO with a TNAM template takes the template's values (docs/formats/armor.md), and the
// player's weapon shows its WNAM static's model (docs/formats/item-records.md).

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct ArmorTemplateTests {
    private static func armor(
        _ formID: UInt32, name: String, value: Int32, template: UInt32? = nil
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(name))
        fields += ESMFixture.field("FULL", ESMFixture.zstring(name))
        if template == nil {
            fields += InventoryFixture.formIDField("MODL", 0x900)
            fields += ESMFixture.field(
                "DATA", InventoryFixture.valueWeightData(value: value, weight: 12)
            )
            var rating = Data()
            rating.appendUInt32(2500)
            fields += ESMFixture.field("DNAM", rating)
        } else {
            fields += ESMFixture.field(
                "DATA", InventoryFixture.valueWeightData(value: value, weight: 1)
            )
        }
        if let template {
            fields += InventoryFixture.formIDField("TNAM", template)
        }
        return ESMFixture.record("ARMO", formID: formID, data: fields)
    }

    @Test func aTemplatedArmourTakesTheTemplateLookAndRatingAndKeepsItsValue() throws {
        let file = try ESMFixture.plugin(records: [
            Self.armor(0x60, name: "Base", value: 40),
            Self.armor(0x61, name: "Child", value: 300, template: 0x60)
        ])
        let loadOrder = LoadOrderPlugins(file: file)
        let store = ItemDefinitionStore(loadOrder: loadOrder)
        let child = try #require(store.armor[0x61])
        #expect(child.armatures == [FormID(0x900)])
        #expect(child.armorRating == 2500)
        #expect(child.itemValue == ItemValue(value: 300, weight: 12))
        #expect(store.definitions[0x61]?.weight == 12)
        #expect(store.definitions[0x61]?.value == 300)
        let catalog = EquipmentCatalog.build(from: loadOrder)
        #expect(catalog.item(FormID(0x61))?.rating == 25)
    }

    @Test func thePlayerWeaponModelIsTheFirstPersonStatic() throws {
        var weapon = ESMFixture.field("EDID", ESMFixture.zstring("Sword"))
        weapon += ESMFixture.field("MODL", ESMFixture.zstring("weapons\\sword.nif"))
        weapon += ESMFixture.field(
            "DATA", InventoryFixture.weaponData(value: 1, weight: 1, damage: 1)
        )
        weapon += ESMFixture.field(
            "DNAM", InventoryFixture.weaponDNAM(animation: 1, speed: 1, reach: 1, flags: 0)
        )
        weapon += InventoryFixture.formIDField("WNAM", 0x71)
        var still = ESMFixture.field("EDID", ESMFixture.zstring("1stPersonSword"))
        still += ESMFixture.field("MODL", ESMFixture.zstring("weapons\\1stpersonsword.nif"))
        let file = try ESMFixture.plugin(records: [
            ESMFixture.record("WEAP", formID: 0x70, data: weapon),
            ESMFixture.record("STAT", formID: 0x71, data: still)
        ])
        let entry = try #require(
            EquipmentCatalog.build(from: LoadOrderPlugins(file: file)).item(FormID(0x70))
        )
        #expect(entry.modelPath == "weapons\\sword.nif")
        #expect(entry.playerModelPath == "weapons\\1stpersonsword.nif")
    }
}
