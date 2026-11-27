// Which WEAP sound each weapon animation event plays (docs/formats/item-records.md, WEAP).

import Foundation
import OpenSkyActorPresentation
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import Testing

struct WeaponSoundEventTests {
    /// NAM9 draws, NAM8 sheathes, TNAM swings; the end of an attack plays nothing.
    @Test func eachEventPlaysItsWeaponSound() throws {
        let weapon = try Weapon(record: ESMFixture.parseRecord(ESMFixture.record(
            "WEAP", formID: 0x300,
            data: ESMFixture.field("DATA", InventoryFixture.weaponData(
                value: 10, weight: 5, damage: 7
            )) + InventoryFixture.formIDField("NAM9", 0x61)
                + InventoryFixture.formIDField("NAM8", 0x62)
                + InventoryFixture.formIDField("TNAM", 0x63)
        )), localized: false).details
        #expect(WeaponSoundEvent.draw.sound(of: weapon) == FormID(0x61))
        #expect(WeaponSoundEvent.sheathe.sound(of: weapon) == FormID(0x62))
        #expect(WeaponSoundEvent.swing(leftHand: true).sound(of: weapon) == FormID(0x63))
        #expect(WeaponSoundEvent.attackEnd.sound(of: weapon) == nil)
    }
}
