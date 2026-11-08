// A worn set the tests change by hand, with one one-handed sword in the right hand.

@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface

@MainActor
final class FakeHandEquipment: EquipmentAccess {
    static let oneHandedSword = FormID(0xA01)

    var worn: [FormID] = []

    func equipped(on _: InventoryHolder) -> [FormID] {
        worn
    }

    func occupancy(of item: FormID) -> EquipmentOccupancy {
        item == Self.oneHandedSword ? EquipmentOccupancy(hands: .rightHand) : .none
    }

    func equip(_ item: FormID, on _: InventoryHolder) throws -> EquipmentChange {
        worn.append(item)
        return EquipmentChange(unequipped: [], changed: true)
    }

    func unequip(_ item: FormID, on _: InventoryHolder) -> Bool {
        let before = worn.count
        worn.removeAll { $0 == item }
        return worn.count != before
    }
}
