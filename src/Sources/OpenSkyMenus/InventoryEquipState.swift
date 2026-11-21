// The equip icon a list row draws, as the `ES_` values of the movie's `InventoryDefines`.
// See docs/engine/inventory-menu.md#list-data.

public import OpenSkyGameData

/// `ES_NONE` to `ES_BOTH_EQUIPPED`: the row's `equipState`.
nonisolated public enum InventoryEquipState: Int, Equatable, Sendable {
    case none = 0
    case equipped = 1
    case leftHand = 2
    case rightHand = 3
    case bothHands = 4

    /// A row held in a hand shows that hand; anything else worn shows the plain icon.
    public init(isEquipped: Bool, hands: HandSlots) {
        if hands == .bothHands {
            self = .bothHands
        } else if hands.contains(.leftHand) {
            self = .leftHand
        } else if hands.contains(.rightHand) {
            self = .rightHand
        } else {
            self = isEquipped ? .equipped : .none
        }
    }
}
