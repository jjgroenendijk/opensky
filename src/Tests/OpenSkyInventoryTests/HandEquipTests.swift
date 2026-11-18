import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyInventory
import OpenSkyInventoryInterface
import Testing

struct HandEquipTests {
    static let sword = FormID(0x100)
    static let dagger = FormID(0x101)
    static let greatsword = FormID(0x102)
    static let shield = FormID(0x103)
    static let helmet = FormID(0x104)

    static func occupancy(_ item: FormID) -> EquipmentOccupancy {
        switch item {
        case sword, dagger: EquipmentOccupancy(hands: .rightHand)
        case greatsword: EquipmentOccupancy(hands: .bothHands)
        case shield: EquipmentOccupancy(hands: .leftHand)
        case helmet: EquipmentOccupancy(slots: BodySlots(rawValue: 1 << 1))
        default: .none
        }
    }

    static func item(_ form: FormID) -> EquippableItem? {
        guard form != helmet else {
            return EquippableItem(occupancy: occupancy(form), modelPath: nil)
        }
        return EquippableItem(occupancy: occupancy(form), modelPath: "w.nif")
    }

    static func state(
        _ counts: [FormID: Int32], equipped: [FormID], leftHand: LeftHandHold? = nil
    ) -> ReferenceInventoryState {
        ReferenceInventoryState(
            stacks: counts.map { InventoryStack(item: $0.key, count: $0.value) },
            equipped: equipped, leftHand: leftHand
        )
    }

    static func equip(
        _ item: FormID, toLeft: Bool, _ state: ReferenceInventoryState
    ) -> HandEquipResult {
        HandEquip.equip(item, toLeft: toLeft, in: state, occupancy: occupancy)
    }

    @Test func aDaggerInTheLeftHandKeepsTheSwordInTheRight() {
        let worn = Self.state([Self.sword: 1, Self.dagger: 1], equipped: [Self.sword])
        let result = Self.equip(Self.dagger, toLeft: true, worn)
        #expect(result.displaced.isEmpty)
        #expect(result.leftHand == LeftHandHold(item: Self.dagger))
        #expect(Set(result.equipped) == [Self.sword, Self.dagger])
    }

    @Test func aSecondCopyMakesAPairAndOneCopyMovesHands() {
        let two = Self.state([Self.sword: 2], equipped: [Self.sword])
        #expect(Self.equip(Self.sword, toLeft: true, two).leftHand
            == LeftHandHold(item: Self.sword, paired: true))
        let one = Self.state([Self.sword: 1], equipped: [Self.sword])
        #expect(Self.equip(Self.sword, toLeft: true, one).leftHand
            == LeftHandHold(item: Self.sword))
        let left = Self.state(
            [Self.sword: 2],
            equipped: [Self.sword],
            leftHand: LeftHandHold(item: Self.sword)
        )
        #expect(Self.equip(Self.sword, toLeft: false, left).leftHand
            == LeftHandHold(item: Self.sword, paired: true))
        let leftOnly = Self.state(
            [Self.sword: 1],
            equipped: [Self.sword],
            leftHand: LeftHandHold(item: Self.sword)
        )
        #expect(Self.equip(Self.sword, toLeft: false, leftOnly).leftHand == nil)
        #expect(Self.equip(Self.sword, toLeft: true, leftOnly).displaced.isEmpty)
    }

    @Test func aShieldOrATwoHanderTakesTheLeftHandWeaponOff() {
        let hold = LeftHandHold(item: Self.dagger)
        let worn = Self.state(
            [Self.sword: 1, Self.dagger: 1, Self.shield: 1, Self.greatsword: 1],
            equipped: [Self.sword, Self.dagger], leftHand: hold
        )
        let shield = Self.equip(Self.shield, toLeft: false, worn)
        #expect(shield.displaced == [Self.dagger])
        #expect(shield.leftHand == nil)
        let both = Self.equip(Self.greatsword, toLeft: false, worn)
        #expect(Set(both.displaced) == [Self.sword, Self.dagger])
        #expect(both.leftHand == nil)
    }

    @Test func aPairLosesOnlyTheCopyInTheTakenHand() {
        let pair = Self.state(
            [Self.sword: 2, Self.dagger: 1, Self.shield: 1], equipped: [Self.sword],
            leftHand: LeftHandHold(item: Self.sword, paired: true)
        )
        let right = Self.equip(Self.dagger, toLeft: false, pair)
        #expect(right.displaced.isEmpty)
        #expect(right.leftHand == LeftHandHold(item: Self.sword))
        let left = Self.equip(Self.dagger, toLeft: true, pair)
        #expect(left.leftHand == LeftHandHold(item: Self.dagger))
        #expect(Set(left.equipped) == [Self.sword, Self.dagger])
        let shield = Self.equip(Self.shield, toLeft: false, pair)
        #expect(shield.leftHand == nil)
        #expect(shield.displaced.isEmpty)
        #expect(Self.equip(Self.sword, toLeft: false, pair).leftHand == pair.leftHand)
    }

    @Test func emptyingAHandKeepsTheOtherCopyOfAPair() {
        let pair = Self.state(
            [Self.sword: 2, Self.helmet: 1], equipped: [Self.sword, Self.helmet],
            leftHand: LeftHandHold(item: Self.sword, paired: true)
        )
        let left = HandEquip.emptying(.leftHand, in: pair, occupancy: Self.occupancy)
        #expect(left.leftHand == nil)
        #expect(left.displaced.isEmpty)
        let right = HandEquip.emptying(.rightHand, in: pair, occupancy: Self.occupancy)
        #expect(right.leftHand == LeftHandHold(item: Self.sword))
        let both = HandEquip.emptying(.bothHands, in: pair, occupancy: Self.occupancy)
        #expect(both.displaced == [Self.sword])
        #expect(both.equipped == [Self.helmet])
        let single = Self.state(
            [Self.sword: 1, Self.dagger: 1], equipped: [Self.sword, Self.dagger],
            leftHand: LeftHandHold(item: Self.dagger)
        )
        #expect(HandEquip.emptying(.leftHand, in: single, occupancy: Self.occupancy).displaced
            == [Self.dagger])
        #expect(HandEquip.emptying(.rightHand, in: single, occupancy: Self.occupancy).displaced
            == [Self.sword])
    }

    static func hands(_ form: FormID) -> HandSlots? {
        item(form).flatMap { $0.isWeapon ? $0.occupancy.hands : nil }
    }

    @Test func eachHandNamesItsWeapon() {
        let hold = LeftHandHold(item: Self.dagger)
        #expect(WornWeapons.resolve(
            in: [Self.sword, Self.dagger, Self.helmet], leftHand: hold, hands: Self.hands
        ) == WornWeapons(right: Self.sword, left: Self.dagger))
        #expect(WornWeapons.resolve(
            in: [Self.sword], leftHand: LeftHandHold(item: Self.sword, paired: true),
            hands: Self.hands
        ) == WornWeapons(right: Self.sword, left: Self.sword))
        #expect(WornWeapons.resolve(in: [Self.sword, Self.dagger], leftHand: nil, hands: Self.hands)
            == WornWeapons(right: Self.sword, left: Self.dagger))
        #expect(WornWeapons.resolve(in: [Self.greatsword], leftHand: nil, hands: Self.hands)
            == WornWeapons(right: Self.greatsword, left: nil))
        #expect(WornWeapons.resolve(in: [Self.helmet], leftHand: nil, hands: Self.hands)
            == WornWeapons(right: nil, left: nil))
        #expect(HandEquip.held(Self.sword, occupancy: Self.occupancy(Self.sword), leftHand: hold)
            == .rightHand)
        #expect(HandEquip.held(Self.dagger, occupancy: Self.occupancy(Self.dagger), leftHand: hold)
            == .leftHand)
    }

    @Test func theStateDropsAHoldItCannotKeep() {
        let unworn = Self.state(
            [Self.sword: 1],
            equipped: [],
            leftHand: LeftHandHold(item: Self.sword)
        )
        #expect(unworn.leftHand == nil)
        let lonePair = Self.state(
            [Self.sword: 1], equipped: [Self.sword],
            leftHand: LeftHandHold(item: Self.sword, paired: true)
        )
        #expect(lonePair.leftHand == nil)
        let pair = Self.state(
            [Self.sword: 2], equipped: [Self.sword],
            leftHand: LeftHandHold(item: Self.sword, paired: true)
        )
        let owner = ReferenceKey.player
        let afterOne = try? pair.removing(Self.sword, count: 1, owner: owner)
        #expect(afterOne?.leftHand == nil)
        #expect(afterOne?.isEquipped(Self.sword) == true)
        let left = Self.state(
            [Self.sword: 1],
            equipped: [Self.sword],
            leftHand: LeftHandHold(item: Self.sword)
        )
        #expect(left.unequipping(Self.sword).leftHand == nil)
        #expect(left.settingEquipped([]).leftHand == nil)
        #expect((try? left.removing(Self.sword, count: 1, owner: owner))?.leftHand == nil)
    }
}
