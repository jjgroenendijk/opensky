// What an actor holds and wears, as the equipment condition functions read it.
// See docs/engine/condition-functions-world.md#equipment.

import Foundation
import OpenSkyFormatsESM

/// The weapon in one hand.
nonisolated public struct EquippedWeaponFacts: Equatable, Sendable {
    public var item: FormID
    /// The WEAP DNAM animation type, nil for hand-to-hand.
    public var animationType: Weapon.AnimationType?
    /// The DNAM skill as an actor-value index, nil when the record names none.
    public var skill: Int32?

    public init(item: FormID, animationType: Weapon.AnimationType?, skill: Int32?) {
        self.item = item
        self.animationType = animationType
        self.skill = skill
    }
}

/// One worn or held item.
nonisolated public struct EquippedItemFacts: Equatable, Sendable {
    /// KWDA, raw FormIDs as the item's plugin spells them.
    public var keywords: [FormID]
    /// An ARMO record: armour or clothing.
    public var isApparel: Bool
    public var value: Int32

    public init(keywords: [FormID], isApparel: Bool, value: Int32) {
        self.keywords = keywords
        self.isApparel = isApparel
        self.value = value
    }
}

nonisolated public struct ActorEquipmentFacts: Equatable, Sendable {
    /// `GetEquippedItemType` codes per hand, the behaviour graph's hand types.
    public var leftHandType: Int32
    public var rightHandType: Int32
    public var rightWeapon: EquippedWeaponFacts?
    public var leftWeapon: EquippedWeaponFacts?
    public var hasShield: Bool
    public var items: [EquippedItemFacts]

    public init(
        leftHandType: Int32 = 0,
        rightHandType: Int32 = 0,
        rightWeapon: EquippedWeaponFacts? = nil,
        leftWeapon: EquippedWeaponFacts? = nil,
        hasShield: Bool = false,
        items: [EquippedItemFacts] = []
    ) {
        self.leftHandType = leftHandType
        self.rightHandType = rightHandType
        self.rightWeapon = rightWeapon
        self.leftWeapon = leftWeapon
        self.hasShield = hasShield
        self.items = items
    }

    /// `GetEquippedItemType` for a casting-source parameter: 0 left, 1 right. The voice
    /// and instant sources hold no item.
    public func itemType(source: Int32) -> Int32 {
        switch source {
        case 0: leftHandType
        case 1: rightHandType
        default: 0
        }
    }

    public func apparel(with keyword: FormID) -> Int {
        items.count { $0.isApparel && $0.keywords.contains(keyword) }
    }
}
