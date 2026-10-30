// Item actions the game refuses with a notice: dropping a key, a quest item, or
// anything in the air, changing gear mid-attack, and marking an item that cannot be a
// favourite. See docs/engine/inventory-menu.md#refused-actions.

import OpenSkyGameData

nonisolated public enum ItemRefusalText: String, GameSettingTextKey {
    case equipWeaponWhileAttacking = "sAnimationCanNotEquipWeapon"
    case equipArmourWhileAttacking = "sAnimationCanNotEquipArmor"
    case unequipWhileAttacking = "sAnimationCanNotUnequip"
    case cannotEquip = "sCantEquipGeneric"
    case cannotUnequip = "sCantUnequipGeneric"
    case cannotEquipEnchanted = "sCanNotEquipWornEnchantment"
    case cannotRemoveWorn = "sCantRemoveWornItem"
    case cannotFavourite = "sCantHotkeyItem"
    case dropInAir = "sNoJumpWarning"
    case dropKey = "sNoKeyDropWarning"
    case dropQuestItem = "sDropQuestItemWarning"
    case dropWhileActing = "sDropEquippedItemWarning"
    case noRoom = "sNotEnoughRoomWarning"
    case eatQuestItem = "sNoEatQuestItem"

    public var fallback: String {
        switch self {
        case .equipWeaponWhileAttacking, .unequipWhileAttacking:
            "You cannot change weapons while attacking."
        case .equipArmourWhileAttacking: "You cannot change armor while attacking."
        case .cannotEquip: "You cannot equip this item."
        case .cannotUnequip: "You cannot unequip this item."
        case .cannotEquipEnchanted: "You cannot equip this item right now."
        case .cannotRemoveWorn: "Unable to remove the worn item."
        case .cannotFavourite: "You cannot favorite that item."
        case .dropInAir: "You can not drop objects while in the air."
        case .dropKey: "You cannot drop keys."
        case .dropQuestItem: "Quest Items cannot be removed from your Inventory."
        case .dropWhileActing: "Current action must complete before item can be dropped."
        case .noRoom: "You do not have enough room to drop this object."
        case .eatQuestItem: "You can not eat quest items."
        }
    }
}

/// One item action the player asks for.
nonisolated public enum ItemRequest: Equatable, Sendable {
    case drop
    case consume
    case equip(isArmour: Bool)
    case unequip
    case favourite
    /// Moving a worn item into a container or a trade.
    case giveWorn
}

nonisolated public struct ItemRequestFacts: Equatable, Sendable {
    public var isKey = false
    /// `Quest Object` alias items. OpenSky does not mark them yet (#1472).
    public var isQuestItem = false
    public var isEquipped = false
    /// Weapons, armour, spells, potions, food, ingredients, poisons, and scrolls.
    public var canBeFavourite = true
    /// An enchanted item whose enchantment the equip runtime cannot apply.
    public var hasUnusableEnchantment = false
    /// The item cannot be worn by the player's race or its slots.
    public var cannotBeWorn = false
    /// A non-playable item, such as a creature's skin, which the player cannot take off.
    public var isNonPlayable = false
    public var playerIsAirborne = false
    public var playerIsAttacking = false
    public var hasDropRoom = true

    public init() {}
}

nonisolated public enum ItemRefusalRule {
    /// The refusal of `request`, or nil when it goes on.
    public static func refusal(_ request: ItemRequest, _ facts: ItemRequestFacts) -> ItemRefusalText? {
        switch request {
        case .drop: dropRefusal(facts)
        case .consume: facts.isQuestItem ? .eatQuestItem : nil
        case let .equip(isArmour): equipRefusal(isArmour: isArmour, facts)
        case .unequip: unequipRefusal(facts)
        case .favourite: facts.canBeFavourite ? nil : .cannotFavourite
        case .giveWorn: facts.isQuestItem ? .cannotRemoveWorn : nil
        }
    }

    private static func dropRefusal(_ facts: ItemRequestFacts) -> ItemRefusalText? {
        if facts.isQuestItem {
            return .dropQuestItem
        }
        if facts.isKey {
            return .dropKey
        }
        if facts.playerIsAirborne {
            return .dropInAir
        }
        if facts.isEquipped, facts.playerIsAttacking {
            return .dropWhileActing
        }
        return facts.hasDropRoom ? nil : .noRoom
    }

    private static func unequipRefusal(_ facts: ItemRequestFacts) -> ItemRefusalText? {
        if facts.playerIsAttacking {
            return .unequipWhileAttacking
        }
        return facts.isNonPlayable ? .cannotUnequip : nil
    }

    private static func equipRefusal(isArmour: Bool, _ facts: ItemRequestFacts) -> ItemRefusalText? {
        if facts.playerIsAttacking {
            return isArmour ? .equipArmourWhileAttacking : .equipWeaponWhileAttacking
        }
        if facts.cannotBeWorn {
            return .cannotEquip
        }
        return facts.hasUnusableEnchantment ? .cannotEquipEnchanted : nil
    }
}
