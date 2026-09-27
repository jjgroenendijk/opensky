// WEAP and AMMO decoders plus the inventory-facing ARMO fields added in
// M12.1.1. Fixtures are synthetic in-code records (InventoryFixture) — never
// extracted game files (AGENTS.md "Legal & IP boundary").
//
// Layouts: UESP "Skyrim Mod:Mod File Format" subpages /WEAP, /AMMO and /ARMO,
// cross-checked against xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas.
// See docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

struct WeaponRecordTests {
    @Test func decodesWeapon() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("IronSword"))
        fields += ESMFixture.field("FULL", ESMFixture.zstring("Iron Sword"))
        fields += ESMFixture.field("MODL", ESMFixture.zstring("weapons\\iron\\sword.nif"))
        fields += ESMFixture.field("DESC", ESMFixture.zstring("A sword."))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.weaponData(value: 25, weight: 9, damage: 7)
        )
        fields += ESMFixture.field(
            "DNAM",
            InventoryFixture.weaponDNAM(
                animation: 1, speed: 1, reach: 0.7, flags: 0x08, skill: 6
            )
        )
        fields += ESMFixture.field(
            "CRDT", InventoryFixture.criticalData(sse: true, damage: 3, spell: 0x0AB)
        )
        fields += InventoryFixture.formIDField("EITM", 0x0CD)
        var charge = Data()
        charge.appendUInt16(400)
        fields += ESMFixture.field("EAMT", charge)
        fields += InventoryFixture.formIDField("ETYP", 0x0001_3F42)
        fields += InventoryFixture.formIDField("CNAM", 0x0002_0000)
        let weapon = try Weapon(
            record: InventoryFixture.record(
                ESMFixture.record("WEAP", formID: 0x55, data: fields)
            ),
            localized: false
        )
        #expect(weapon.fields.modelPath == "weapons\\iron\\sword.nif")
        #expect(weapon.description == .inline("A sword."))
        #expect(weapon.itemValue == ItemValue(value: 25, weight: 9))
        #expect(weapon.damage == 7)
        #expect(weapon.animationType == .oneHandSword)
        #expect(weapon.speed == 1)
        #expect(weapon.reach == 0.7)
        #expect(weapon.flags == [.cannotDrop])
        #expect(weapon.skill == 6)
        #expect(weapon.stagger == 0.75)
        #expect(weapon.criticalData?.damage == 3)
        #expect(weapon.criticalData?.effect == FormID(0x0AB))
        #expect(weapon.enchantment == FormID(0x0CD))
        #expect(weapon.enchantmentCharge == 400)
        #expect(weapon.equipType == FormID(0x0001_3F42))
        #expect(weapon.template == FormID(0x0002_0000))
    }

    /// The SPEL link sits at 0x10 in the 24-byte SSE CRDT and at 0x0C in the
    /// 16-byte classic form, so both must decode to the same spell.
    @Test func criticalDataHandlesBothLayouts() throws {
        for sse in [true, false] {
            let fields = ESMFixture.field(
                "CRDT", InventoryFixture.criticalData(sse: sse, damage: 12, spell: 0x0FE)
            )
            let weapon = try Weapon(
                record: InventoryFixture.record(ESMFixture.record("WEAP", data: fields)),
                localized: false
            )
            #expect(weapon.criticalData?.damage == 12)
            #expect(weapon.criticalData?.onDeath == true)
            #expect(weapon.criticalData?.effect == FormID(0x0FE))
        }
    }

    /// An unrecognised CRDT length decodes as "no critical data" rather than
    /// being force-fit onto one of the two known layouts.
    @Test func ignoresUnknownCriticalLayout() throws {
        let fields = ESMFixture.field("CRDT", Data(count: 20))
        let weapon = try Weapon(
            record: InventoryFixture.record(ESMFixture.record("WEAP", data: fields)),
            localized: false
        )
        #expect(weapon.criticalData == nil)
    }

    @Test func skillNegativeOneDecodesAsNoSkill() throws {
        let fields = ESMFixture.field(
            "DNAM",
            InventoryFixture.weaponDNAM(
                animation: 200, speed: 1, reach: 1, flags: 0, skill: -1
            )
        )
        let weapon = try Weapon(
            record: InventoryFixture.record(ESMFixture.record("WEAP", data: fields)),
            localized: false
        )
        #expect(weapon.skill == nil)
        // 200 is outside the documented 0...9 set, so it decodes as unknown.
        #expect(weapon.animationType == nil)
    }

    @Test func rejectsWrongTypeAndTruncatedStructs() {
        #expect(throws: ESMError.self) {
            _ = try Weapon(
                record: InventoryFixture.record(ESMFixture.record("AMMO", data: Data())),
                localized: false
            )
        }
        #expect(throws: ESMError.self) {
            _ = try Weapon(
                record: InventoryFixture.record(
                    ESMFixture.record("WEAP", data: ESMFixture.field("DATA", Data(count: 9)))
                ),
                localized: false
            )
        }
        #expect(throws: ESMError.self) {
            _ = try Weapon(
                record: InventoryFixture.record(
                    ESMFixture.record("WEAP", data: ESMFixture.field("DNAM", Data(count: 99)))
                ),
                localized: false
            )
        }
    }

    @Test func emptyRecordDecodesToDefaults() throws {
        let weapon = try Weapon(
            record: InventoryFixture.record(ESMFixture.record("WEAP", data: Data())),
            localized: false
        )
        #expect(weapon.itemValue == .zero)
        #expect(weapon.criticalData == nil)
        #expect(weapon.animationType == nil)
    }
}

struct AmmunitionRecordTests {
    @Test func decodesSSELayout() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("IronArrow"))
        fields += ESMFixture.field("DESC", ESMFixture.zstring(""))
        fields += ESMFixture.field(
            "DATA",
            InventoryFixture.ammoData(
                projectile: 0x0003_4182, flags: 0x04, damage: 8, value: 1, weight: 0.1
            )
        )
        let ammo = try Ammunition(
            record: InventoryFixture.record(
                ESMFixture.record("AMMO", formID: 0x66, data: fields)
            ),
            localized: false
        )
        #expect(ammo.projectile == FormID(0x0003_4182))
        #expect(ammo.flags == [.nonBolt])
        #expect(ammo.damage == 8)
        #expect(ammo.itemValue == ItemValue(value: 1, weight: 0.1))
    }

    /// A classic 16-byte DATA stops after the gold value; weight decodes as 0.
    @Test func classicLayoutLeavesWeightZero() throws {
        let fields = ESMFixture.field(
            "DATA",
            InventoryFixture.ammoData(
                projectile: 0, flags: 0, damage: 10, value: 2, weight: nil
            )
        )
        let ammo = try Ammunition(
            record: InventoryFixture.record(ESMFixture.record("AMMO", data: fields)),
            localized: false
        )
        #expect(ammo.projectile == nil)
        #expect(ammo.itemValue == ItemValue(value: 2, weight: 0))
    }

    @Test func rejectsWrongTypeAndTruncatedData() {
        #expect(throws: ESMError.self) {
            _ = try Ammunition(
                record: InventoryFixture.record(ESMFixture.record("WEAP", data: Data())),
                localized: false
            )
        }
        #expect(throws: ESMError.self) {
            _ = try Ammunition(
                record: InventoryFixture.record(
                    ESMFixture.record("AMMO", data: ESMFixture.field("DATA", Data(count: 15)))
                ),
                localized: false
            )
        }
    }

    @Test func emptyRecordDecodesToDefaults() throws {
        let ammo = try Ammunition(
            record: InventoryFixture.record(ESMFixture.record("AMMO", data: Data())),
            localized: false
        )
        #expect(ammo.projectile == nil)
        #expect(ammo.itemValue == .zero)
    }
}

struct ArmorInventoryFieldTests {
    @Test func decodesValueWeightKeywordsAndRating() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("ArmorIronCuirass"))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.valueWeightData(value: 125, weight: 30)
        )
        var rating = Data()
        rating.appendUInt32(2500)
        fields += ESMFixture.field("DNAM", rating)
        fields += InventoryFixture.keywordFields([0x0006_BBD2, 0x0008_F958])
        let armor = try Armor(
            record: InventoryFixture.record(
                ESMFixture.record("ARMO", formID: 0x88, data: fields)
            ),
            localized: false
        )
        #expect(armor.itemValue == ItemValue(value: 125, weight: 30))
        #expect(armor.armorRating == 2500)
        #expect(armor.keywords.keywords == [FormID(0x0006_BBD2), FormID(0x0008_F958)])
    }
}

/// ARMA decode, including the DNAM draw priorities equip-slot resolution
/// compares (issue #178). Split out of `AppearanceRecordDecodeTests` when that
/// suite outgrew the strict-lint type-body cap; the ARMA record is equipment
/// data, so this is also where it belongs.
struct ArmorAddonRecordTests {
    @Test func decodesArmorAddon() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("IronCuirassAA"))
        var bod2 = Data()
        bod2.appendUInt32(0b0100) // body
        bod2.appendUInt32(1)
        fields += ESMFixture.field("BOD2", bod2)
        fields += armaFormID("RNAM", 0x19)
        fields += dnamField(male: 5, female: 7, weaponAdjust: 0.8)
        fields += ESMFixture.field("MOD2", ESMFixture.zstring("armor\\iron\\m.nif"))
        fields += ESMFixture.field("MOD3", ESMFixture.zstring("armor\\iron\\f.nif"))
        fields += armaFormID("MODL", 0x0001_D4D4)
        fields += armaFormID("MODL", 0x0001_E5E5)
        let addon = try ArmorAddon(
            record: InventoryFixture.record(ESMFixture.record("ARMA", formID: 0x6000, data: fields))
        )
        #expect(addon.formID == FormID(0x6000))
        #expect(addon.editorID == "IronCuirassAA")
        #expect(addon.bodyTemplate?.slots == [.body])
        #expect(addon.primaryRace == FormID(0x19))
        #expect(addon.maleModelPath == "armor\\iron\\m.nif")
        #expect(addon.femaleModelPath == "armor\\iron\\f.nif")
        #expect(addon.additionalRaces == [FormID(0x0001_D4D4), FormID(0x0001_E5E5)])
        #expect(addon.malePriority == 5)
        #expect(addon.femalePriority == 7)
        #expect(addon.weaponAdjust == 0.8)
        #expect(addon.priority(female: false) == 5)
        #expect(addon.priority(female: true) == 7)
    }

    @Test func armorAddonOptionalFieldsNilWhenAbsent() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("BareAA"))
        let addon = try ArmorAddon(
            record: InventoryFixture.record(ESMFixture.record("ARMA", formID: 1, data: fields))
        )
        #expect(addon.primaryRace == nil)
        #expect(addon.maleModelPath == nil)
        #expect(addon.femaleModelPath == nil)
        #expect(addon.additionalRaces.isEmpty)
        #expect(addon.bodyTemplate == nil)
        // No DNAM reads as the naked-body priority, which is what the data
        // means: a DNAM-less armature layers below everything authored.
        #expect(addon.malePriority == 0)
        #expect(addon.femalePriority == 0)
        #expect(addon.weaponAdjust == 0)
    }

    /// A DNAM shorter than the documented 12 bytes decodes as far as it
    /// reaches. Refusing the record would drop an armature that renders fine
    /// over a field that only affects layering.
    @Test func armorAddonTruncatedDNAMDegradesRatherThanThrowing() throws {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring("ShortAA"))
        fields += ESMFixture.field("DNAM", Data([3, 4]))
        let addon = try ArmorAddon(
            record: InventoryFixture.record(ESMFixture.record("ARMA", formID: 2, data: fields))
        )
        #expect(addon.malePriority == 3)
        #expect(addon.femalePriority == 4)
        #expect(addon.weaponAdjust == 0)

        var empty = ESMFixture.field("EDID", ESMFixture.zstring("EmptyDNAMAA"))
        empty += ESMFixture.field("DNAM", Data())
        let bare = try ArmorAddon(
            record: InventoryFixture.record(ESMFixture.record("ARMA", formID: 3, data: empty))
        )
        #expect(bare.malePriority == 0)
    }

    @Test func armorAddonRejectsOtherRecordTypes() throws {
        let bytes = ESMFixture.record("ARMO", formID: 1, data: Data())
        #expect(throws: ESMError.self) {
            _ = try ArmorAddon(record: InventoryFixture.record(bytes))
        }
    }
}

private func armaFormID(_ type: String, _ value: UInt32) -> Data {
    var data = Data()
    data.appendUInt32(value)
    return ESMFixture.field(type, data)
}
