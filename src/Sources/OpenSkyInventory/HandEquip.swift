// Which hand each worn weapon holds, and what an equip into one hand displaces.
// Pure: the equipped set, the left hand, and the item occupancies in; the new set
// out. See docs/engine/inventory-state.md#the-left-hand.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface

/// The worn state an equip leaves, and the items it took off.
nonisolated public struct HandEquipResult: Equatable, Sendable {
    public let equipped: [FormID]
    public let leftHand: LeftHandHold?
    public let displaced: [FormID]
}

nonisolated public enum HandEquip {
    /// The hands `item` holds now. The left-hand item holds the left hand, or both
    /// hands when a second copy is in the right one.
    public static func held(
        _ item: FormID, occupancy: EquipmentOccupancy, leftHand: LeftHandHold?
    ) -> HandSlots {
        guard let leftHand, leftHand.item == item else { return occupancy.hands }
        return leftHand.paired ? .bothHands : .leftHand
    }

    /// Equips one copy of `item`. With `toLeft`, the copy goes to the left hand; the
    /// caller allows that only for a one-handed weapon.
    public static func equip(
        _ item: FormID,
        toLeft: Bool,
        in state: ReferenceInventoryState,
        occupancy: (FormID) -> EquipmentOccupancy
    ) -> HandEquipResult {
        let incoming = occupancy(item)
        let hold = state.leftHand
        let copies = state.count(of: item)
        var takes = incoming.hands
        var newHold = hold
        if toLeft {
            takes = .leftHand
            let inRight = state.isEquipped(item) && (hold?.item != item || hold?.paired == true)
            if hold?.item == item {
                return HandEquipResult(equipped: state.equipped, leftHand: hold, displaced: [])
            }
            newHold = LeftHandHold(item: item, paired: inRight && copies >= 2)
        } else if let hold, hold.item == item {
            guard !hold.paired else {
                return HandEquipResult(equipped: state.equipped, leftHand: hold, displaced: [])
            }
            newHold = copies >= 2 ? LeftHandHold(item: item, paired: true) : nil
        }
        let wanted = EquipmentOccupancy(
            slots: incoming.slots, hands: takes, ammunition: incoming.ammunition
        )
        var displaced: [FormID] = []
        for worn in state.equipped where worn != item {
            if let hold, hold.item == worn {
                // A new left-hand item keeps its hold: the old one only loses its pair.
                switch pairFate(hold, losing: takes) {
                case .kept: break
                case let .held(remaining) where !toLeft: newHold = remaining
                case .held: break
                case .removed:
                    if newHold?.item == worn {
                        newHold = nil
                    }
                    displaced.append(worn)
                }
                continue
            }
            if occupancy(worn).conflicts(with: wanted) {
                displaced.append(worn)
            }
        }
        let equipped = state.equipped.filter { !displaced.contains($0) } + [item]
        return HandEquipResult(equipped: equipped, leftHand: newHold, displaced: displaced)
    }

    /// Takes worn weapons out of `hands`, as readying a spell does. A pair loses only
    /// the copy in an emptied hand.
    public static func emptying(
        _ hands: HandSlots,
        in state: ReferenceInventoryState,
        occupancy: (FormID) -> EquipmentOccupancy
    ) -> HandEquipResult {
        var newHold = state.leftHand
        var displaced: [FormID] = []
        for worn in state.equipped {
            if let hold = state.leftHand, hold.item == worn {
                switch pairFate(hold, losing: hands) {
                case .kept: break
                case let .held(remaining): newHold = remaining
                case .removed:
                    newHold = nil
                    displaced.append(worn)
                }
            } else if occupancy(worn).hands.overlaps(hands) {
                displaced.append(worn)
            }
        }
        let equipped = state.equipped.filter { !displaced.contains($0) }
        return HandEquipResult(equipped: equipped, leftHand: newHold, displaced: displaced)
    }

    private enum PairFate: Equatable {
        case kept
        /// Still worn, holding fewer hands: the new hold, nil for the right hand only.
        case held(LeftHandHold?)
        case removed
    }

    /// What happens to the left-hand item when something takes `hands`.
    private static func pairFate(_ hold: LeftHandHold, losing hands: HandSlots) -> PairFate {
        let left = hands.contains(.leftHand)
        let right = hands.contains(.rightHand)
        guard hold.paired else { return left ? .removed : .kept }
        switch (left, right) {
        case (true, true): return .removed
        case (true, false): return .held(nil)
        case (false, true): return .held(LeftHandHold(item: hold.item))
        case (false, false): return .kept
        }
    }
}
