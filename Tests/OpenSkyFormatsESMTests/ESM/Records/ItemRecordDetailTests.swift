// The xEdit-named fields of item records that no game system reads yet.
// Synthetic records only. Layout: docs/formats/item-records.md.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ItemRecordDetailTests {
    private typealias Fixture = RecordDetailFixture

    @Test func armorReadsEveryDetailField() throws {
        var fields = Fixture.boundsField()
        fields += Fixture.string("DESC", "Plate")
        fields += Fixture.string("ICON", "m.dds") + Fixture.string("MICO", "mm.dds")
        fields += Fixture.string("ICO2", "f.dds") + Fixture.string("MIC2", "fm.dds")
        fields += Fixture.string("BMCT", "ragdoll")
        fields += Fixture.formIDs(["YNAM", "ZNAM", "ETYP", "BIDS"], from: 0x10)
        fields += Fixture.destructibleFields()
        let armor = try Armor(record: Fixture.record("ARMO", fields), localized: false)
        let details = armor.details
        #expect(armor.skipped.isEmpty)
        #expect(Fixture.isFixtureBounds(details.bounds))
        #expect(details.description == .inline("Plate"))
        #expect([
            details.maleIconPath,
            details.maleMessageIconPath,
            details.femaleIconPath,
            details.femaleMessageIconPath,
            details.ragdollConstraintTemplate
        ] == ["m.dds", "mm.dds", "f.dds", "fm.dds", "ragdoll"])
        #expect([
            details.pickupSound, details.dropSound, details.equipType, details.bashImpactDataSet
        ] == Fixture.expectedIDs(4, from: 0x10))
        #expect(details.destructible?.health == 50)
        #expect(details.destructible?.stages.first?.isClosed == true)
        #expect(details.scriptData.scripts.isEmpty)
    }

    @Test func weaponReadsEveryDetailField() throws {
        let soundTypes = ["SNAM", "XNAM", "NAM7", "TNAM", "UNAM", "NAM9", "NAM8"]
        var fields = Fixture.string("MOD3", "scope.nif")
        fields += ESMFixture.field("MO3T", Data(count: 12))
        fields += Fixture.string("NNAM", "WeaponNode")
        fields += Fixture.formIDs(["EFSD", "WNAM", "BAMT"], from: 0x10)
        fields += Fixture.formIDs(soundTypes, from: 0x20)
        fields += ESMFixture.field("VNAM", Fixture.uint32(2))
        fields += Fixture.destructibleFields()
        let weapon = try Weapon(record: Fixture.record("WEAP", fields), localized: false)
        let details = weapon.details
        #expect(weapon.skipped.isEmpty)
        #expect(details.scopeModel?.path == "scope.nif")
        #expect(details.embeddedWeaponNode == "WeaponNode")
        #expect([details.scopeEffect, details.firstPersonModel, details.alternateBlockMaterial]
            == Fixture.expectedIDs(3, from: 0x10))
        #expect([
            details.attackSound,
            details.attackSound2D,
            details.attackLoopSound,
            details.attackFailSound,
            details.idleSound,
            details.equipSound,
            details.unequipSound
        ] == Fixture.expectedIDs(soundTypes.count, from: 0x20))
        #expect(details.detectionSoundLevel == 2)
        #expect(details.destructible?.health == 50)
    }

    @Test func lightReadsEveryDetailField() throws {
        var fields = ESMFixture.field("DATA", Data(count: 48))
        fields += Fixture.boundsField()
        fields += Fixture.string("MODL", "torch.nif")
        fields += Fixture.string("FULL", "Torch")
        fields += Fixture.string("ICON", "torch.dds") + Fixture.string("MICO", "torchm.dds")
        fields += Fixture.formIDs(["SNAM", "LNAM"], from: 0x10)
        fields += Fixture.destructibleFields()
        let light = try LightRecord(record: Fixture.record("LIGH", fields), localized: false)
        let details = light.details
        #expect(light.skipped.isEmpty)
        #expect(Fixture.isFixtureBounds(details.bounds))
        #expect(details.model?.path == "torch.nif")
        #expect(details.name == .inline("Torch"))
        #expect([details.iconPath, details.messageIconPath] == ["torch.dds", "torchm.dds"])
        #expect([details.sound, details.lensFlare] == Fixture.expectedIDs(2, from: 0x10))
        #expect(details.destructible?.health == 50)
        #expect(details.scriptData.scripts.isEmpty)
    }

    @Test func projectileReadsEveryDetailField() throws {
        var fields = Fixture.string("FULL", "Arrow")
        fields += Fixture.string("MODL", "arrow.nif")
        fields += ESMFixture.field("MODT", Data([1, 2, 3]))
        fields += Fixture.string("NAM1", "flash.nif")
        fields += ESMFixture.field("NAM2", Data([4, 5]))
        fields += Fixture.destructibleFields()
        let projectile = try Projectile(record: Fixture.record("PROJ", fields))
        let details = projectile.details
        #expect(projectile.skipped.isEmpty)
        #expect(details.name == .inline("Arrow"))
        #expect(details.modelTextureHashes == Data([1, 2, 3]))
        #expect(details.muzzleFlashModelPath == "flash.nif")
        #expect(details.muzzleFlashTextureHashes == Data([4, 5]))
        #expect(details.destructible?.health == 50)
    }

    @Test func descriptionsAndInventoryArtAreRead() throws {
        let description = Fixture.string("DESC", "Text")
        let ammo = try Ammunition(record: Fixture.record("AMMO", description), localized: false)
        #expect(ammo.description == .inline("Text"))
        #expect(ammo.skipped.isEmpty)
        let characterClass = try CharacterClass(
            record: Fixture.record("CLAS", description), localized: false
        )
        #expect(characterClass.description == .inline("Text"))
        #expect(characterClass.skipped.isEmpty)
        let book = try Book(
            record: Fixture.record("BOOK", ESMFixture.field("INAM", Fixture.uint32(0x10))),
            localized: false
        )
        #expect(book.inventoryArt == FormID(0x10))
        #expect(book.skipped.isEmpty)
    }
}
