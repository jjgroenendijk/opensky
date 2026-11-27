// A WEAP with a CNAM template takes the template's values (docs/formats/item-records.md).

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct WeaponTemplateTests {
    private static func weapon(
        _ formID: UInt32, name: String, damage: UInt16, value: Int32, template: UInt32? = nil
    ) throws -> Weapon {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(name))
        fields += ESMFixture.field("FULL", ESMFixture.zstring(name))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.weaponData(value: value, weight: 9, damage: damage)
        )
        fields += ESMFixture.field(
            "DNAM",
            InventoryFixture.weaponDNAM(animation: 1, speed: 1.25, reach: 0.7, flags: 0)
        )
        if let template {
            fields += InventoryFixture.formIDField("CNAM", template)
        }
        return try Weapon(
            record: InventoryFixture.record(ESMFixture.record(
                "WEAP",
                formID: formID,
                data: fields
            )),
            localized: false
        )
    }

    @Test func aTemplatedWeaponTakesTheCombatValuesAndKeepsItsName() throws {
        let base = try Self.weapon(0x60, name: "Base", damage: 9, value: 40)
        let child = try Self.weapon(0x61, name: "Child", damage: 1, value: 300, template: 0x60)
        let grandchild = try Self.weapon(0x62, name: "Grand", damage: 2, value: 5, template: 0x61)
        let resolved = ItemDefinitionStore.inheritingTemplates(
            [0x60: base, 0x61: child, 0x62: grandchild]
        )
        #expect(resolved[0x61]?.damage == 9)
        #expect(resolved[0x61]?.speed == 1.25)
        #expect(resolved[0x61]?.fields.name == child.fields.name)
        #expect(resolved[0x61]?.itemValue.value == 300)
        #expect(resolved[0x62]?.damage == 9)
    }

    @Test func aLoopOrAMissingTemplateLeavesTheWeapon() throws {
        let first = try Self.weapon(0x70, name: "First", damage: 3, value: 1, template: 0x71)
        let second = try Self.weapon(0x71, name: "Second", damage: 4, value: 1, template: 0x70)
        let orphan = try Self.weapon(0x72, name: "Orphan", damage: 5, value: 1, template: 0x99)
        let resolved = ItemDefinitionStore.inheritingTemplates(
            [0x70: first, 0x71: second, 0x72: orphan]
        )
        #expect(resolved.count == 3)
        #expect(resolved[0x72]?.damage == 5)
        let damages = Set([resolved[0x70]?.damage, resolved[0x71]?.damage].compactMap(\.self))
        #expect(damages.isSubset(of: [3, 4]))
    }
}
