// Which carried items an NPC equips beside its outfit: the best melee weapon, arrows
// for a bow, then armour and a shield in the slots and hands still free.

import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct CarriedEquipmentTests {
    private static let sword = FormID(0x10)
    private static let greatsword = FormID(0x11)
    private static let bow = FormID(0x12)
    private static let fists = FormID(0x13)
    private static let shield = FormID(0x20)
    private static let cuirass = FormID(0x21)
    private static let betterCuirass = FormID(0x22)
    private static let potion = FormID(0x30)
    private static let ironArrow = FormID(0x40)
    private static let steelArrow = FormID(0x41)
    private static let bolt = FormID(0x42)

    private static let catalog = EquipmentCatalog(items: [
        sword.rawValue: weapon(.rightHand, .oneHandSword, damage: 8),
        greatsword.rawValue: weapon(.bothHands, .twoHandSword, damage: 17),
        bow.rawValue: weapon(.bothHands, .bow, damage: 20),
        fists.rawValue: weapon(.rightHand, .other, damage: 30),
        shield.rawValue: EquippableItem(
            occupancy: EquipmentOccupancy(slots: BodySlots(rawValue: 1 << 9), hands: .leftHand),
            modelPath: nil, rating: 20
        ),
        cuirass.rawValue: armour(slots: 1 << 2, rating: 25),
        betterCuirass.rawValue: armour(slots: 1 << 2, rating: 31),
        potion.rawValue: EquippableItem(occupancy: .none, modelPath: nil),
        ironArrow.rawValue: ammunition(firedBy: .bow, damage: 8),
        steelArrow.rawValue: ammunition(firedBy: .bow, damage: 10),
        bolt.rawValue: ammunition(firedBy: .crossbow, damage: 18)
    ])

    @Test func theStrongestMeleeWeaponWinsOverABow() {
        let picks = Self.catalog.carriedPicks(
            worn: [], carried: [Self.bow, Self.sword, Self.greatsword, Self.fists]
        )
        #expect(picks == [Self.greatsword])
    }

    /// An archer's style multiplies a bow's damage past the melee weapons'.
    @Test func aMissileStyleHoldsTheBow() {
        let archer = WeaponPreference(melee: 0.83, ranged: 3.2, staff: 1)
        let warrior = WeaponPreference(melee: 1, ranged: 0.3, staff: 1)
        let carried = [Self.sword, Self.bow, Self.steelArrow]
        #expect(Self.catalog.carriedPicks(worn: [], carried: carried, preference: archer)
            == [Self.bow, Self.steelArrow])
        #expect(Self.catalog.carriedPicks(worn: [], carried: carried, preference: warrior)
            == [Self.sword])
    }

    @Test func aBowIsHeldWithItsBestArrows() {
        let picks = Self.catalog.carriedPicks(
            worn: [], carried: [Self.bolt, Self.ironArrow, Self.bow, Self.steelArrow]
        )
        #expect(picks == [Self.bow, Self.steelArrow])
    }

    @Test func arrowsStayInTheBagWithoutABow() {
        let picks = Self.catalog.carriedPicks(worn: [], carried: [Self.sword, Self.steelArrow])
        #expect(picks == [Self.sword])
    }

    @Test func aShieldGoesWithAOneHandedWeaponOnly() {
        let oneHanded = Self.catalog.carriedPicks(worn: [], carried: [Self.shield, Self.sword])
        let twoHanded = Self.catalog.carriedPicks(
            worn: [], carried: [Self.shield, Self.greatsword]
        )
        #expect(oneHanded == [Self.sword, Self.shield])
        #expect(twoHanded == [Self.greatsword])
    }

    @Test func armourFillsOnlyFreeSlotsAndTheBestPieceWins() {
        let free = Self.catalog.carriedPicks(
            worn: [], carried: [Self.cuirass, Self.betterCuirass, Self.potion]
        )
        let covered = Self.catalog.carriedPicks(worn: [Self.cuirass], carried: [Self.betterCuirass])
        #expect(free == [Self.betterCuirass])
        #expect(covered.isEmpty)
    }

    @Test func aWornShieldLeavesRoomForAOneHandedWeaponOnly() {
        let picks = Self.catalog.carriedPicks(
            worn: [Self.shield], carried: [Self.greatsword, Self.sword]
        )
        let twoHandedOnly = Self.catalog.carriedPicks(
            worn: [Self.shield], carried: [Self.greatsword]
        )
        #expect(picks == [Self.sword])
        #expect(twoHandedOnly.isEmpty)
    }

    private static func weapon(
        _ hands: HandSlots, _ type: Weapon.AnimationType, damage: Float
    ) -> EquippableItem {
        EquippableItem(
            occupancy: EquipmentOccupancy(hands: hands),
            modelPath: "weapon.nif", animationType: type, rating: damage
        )
    }

    private static func ammunition(
        firedBy type: Weapon.AnimationType, damage: Float
    ) -> EquippableItem {
        EquippableItem(
            occupancy: EquipmentOccupancy(ammunition: true),
            modelPath: "arrow.nif", animationType: type, rating: damage
        )
    }

    private static func armour(slots: UInt32, rating: Float) -> EquippableItem {
        EquippableItem(
            occupancy: EquipmentOccupancy(slots: BodySlots(rawValue: slots)),
            modelPath: nil, rating: rating
        )
    }
}
