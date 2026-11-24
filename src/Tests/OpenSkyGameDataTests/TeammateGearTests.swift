// What a teammate wears from what it holds: per body slot the best armour rating, a
// later slot's pick replacing an earlier one it overlaps, and the best weapon.

import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct TeammateGearTests {
    private static let robes = FormID(0x10)
    private static let cuirass = FormID(0x11)
    private static let betterCuirass = FormID(0x12)
    private static let hood = FormID(0x13)
    private static let fullHelm = FormID(0x14)
    private static let sword = FormID(0x20)
    private static let arrows = FormID(0x30)

    private static func armour(_ slots: UInt32, rating: Float) -> EquippableItem {
        EquippableItem(
            occupancy: EquipmentOccupancy(slots: BodySlots(rawValue: slots)),
            modelPath: nil, rating: rating
        )
    }

    private static let catalog = EquipmentCatalog(items: [
        robes.rawValue: armour(1 << 2, rating: 0),
        cuirass.rawValue: armour(1 << 2, rating: 25),
        betterCuirass.rawValue: armour(1 << 2, rating: 31),
        hood.rawValue: armour(1 << 1, rating: 5),
        // Covers the hair and the head, so it beats the hood in the hair slot first.
        fullHelm.rawValue: armour(1 << 0 | 1 << 1, rating: 17),
        sword.rawValue: EquippableItem(
            occupancy: EquipmentOccupancy(hands: .rightHand), modelPath: "sword.nif",
            animationType: .oneHandSword, rating: 8
        ),
        arrows.rawValue: EquippableItem(
            occupancy: EquipmentOccupancy(ammunition: true), modelPath: "arrow.nif",
            animationType: .bow, rating: 8
        )
    ])

    @Test func eachSlotTakesItsHighestRating() {
        let picks = Self.catalog.teammateArmour([
            Self.robes, Self.cuirass, Self.betterCuirass, Self.hood, Self.fullHelm, Self.sword
        ])
        #expect(picks == [Self.fullHelm, Self.betterCuirass])
    }

    @Test func clothingStillFillsAnEmptySlotAndATieKeepsTheFirst() {
        #expect(Self.catalog.teammateArmour([Self.robes, Self.robes]) == [Self.robes])
        let tie = EquipmentCatalog(items: [
            Self.cuirass.rawValue: Self.armour(1 << 2, rating: 25),
            Self.betterCuirass.rawValue: Self.armour(1 << 2, rating: 25)
        ])
        #expect(tie.teammateArmour([Self.betterCuirass, Self.cuirass]) == [Self.betterCuirass])
    }

    @Test func weaponPicksSkipArmour() {
        let picks = Self.catalog.weaponPicks(
            worn: [],
            held: [Self.cuirass, Self.sword, Self.arrows]
        )
        #expect(picks == [Self.sword])
    }

    /// A fast light weapon can beat a slow heavy one, and a bow counts its speed at a fifth.
    @Test func theWeaponScoreCountsSpeed() {
        var dagger = EquippableItem(
            occupancy: EquipmentOccupancy(hands: .rightHand), modelPath: "dagger.nif",
            animationType: .oneHandDagger, rating: 6
        )
        dagger.speed = 1.3
        var mace = EquippableItem(
            occupancy: EquipmentOccupancy(hands: .rightHand), modelPath: "mace.nif",
            animationType: .oneHandMace, rating: 7
        )
        mace.speed = 0.8
        let catalog = EquipmentCatalog(items: [0x50: dagger, 0x51: mace])
        let style = WeaponPreference(melee: 1, ranged: 1, staff: 1)
        #expect(catalog.weaponPicks(worn: [], held: [FormID(0x51), FormID(0x50)], preference: style)
            == [FormID(0x50)])
        #expect(style.score(dagger) == 6 * 1.3)
    }
}
