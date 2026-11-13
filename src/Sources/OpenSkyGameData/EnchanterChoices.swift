// What the arcane enchanter's menu offers and what the player chose there.
// See docs/engine/enchanting.md#enchanting-menu.

public import OpenSkyFormatsESM

/// The texts of the enchanting menu's tabs, questions, and notices.
nonisolated public enum EnchantingMenuText: String, GameSettingTextKey {
    case disenchant = "sDisenchant"
    case item = "sItem"
    case enchantment = "sEnchantment"
    case soulGem = "sSoulGem"
    case confirmDisenchant = "sConfirmDisenchant"
    /// `%s` is the learnt enchantment's name.
    case learned = "sEnchantmentsLearned"
    case alreadyKnown = "sEnchantmentKnown"
    case confirmEnchant = "sEnchantItem"
    case mustChoose = "sEnchantMustChooseItems"
    case insufficientCharge = "sEnchantInsufficientCharge"
    case doesNotFit = "sEnchantArmorIncompatible"

    public var fallback: String {
        switch self {
        case .disenchant: "Disenchant"
        case .item: "Item"
        case .enchantment: "Enchantment"
        case .soulGem: "Soul Gem"
        case .confirmDisenchant: "Are you sure you want to destroy this item and learn its effects?"
        case .learned: "You learned the %s enchantment from destroying this item."
        case .alreadyKnown: "The enchantment on this item is already known"
        case .confirmEnchant: "Enchant item?"
        case .mustChoose: "Choose an item, enchantment, and soul gem"
        case .insufficientCharge: "Insufficient charge for enchantment"
        case .doesNotFit: "Chosen enchantment cannot be applied to this item"
        }
    }
}

/// One carried item the enchanter can take.
nonisolated public struct EnchanterItem: Equatable, Sendable {
    public let id: FormID
    public let name: String
    /// A disenchant row whose enchantment the player knows already.
    public var isKnown = false

    public init(id: FormID, name: String) {
        self.id = id
        self.name = name
    }
}

/// One known base enchantment.
nonisolated public struct EnchanterBase: Equatable, Sendable {
    public let key: ReferenceKey
    public let name: String

    public init(key: ReferenceKey, name: String) {
        self.key = key
        self.name = name
    }
}

/// One filled soul gem: the gem record and the soul in it.
nonisolated public struct EnchanterGem: Equatable, Sendable {
    public let item: FormID
    public let soul: UInt8
    public let name: String

    public init(item: FormID, soul: UInt8, name: String) {
        self.item = item
        self.soul = soul
        self.name = name
    }
}

/// The four tabs of the enchanting menu.
nonisolated public struct EnchanterChoices: Equatable, Sendable {
    /// Enchanted items to destroy, known enchantments included.
    public var disenchantable: [EnchanterItem] = []
    /// Plain weapons and apparel.
    public var enchantable: [EnchanterItem] = []
    public var enchantments: [EnchanterBase] = []
    public var gems: [EnchanterGem] = []

    public init() {}
}

/// The text an enchanter action shows, and whether the action happened.
nonisolated public struct EnchanterAnswer: Equatable, Sendable {
    public let text: String
    public let done: Bool

    public init(text: String, done: Bool) {
        self.text = text
        self.done = done
    }
}

/// What the player chose to make.
nonisolated public struct EnchanterSelection: Equatable, Sendable {
    public var item: FormID?
    public var bases: [ReferenceKey] = []
    public var gem: EnchanterGem?
    /// A name the player typed; nil keeps the made name.
    public var name: String?

    public init() {}

    public var isComplete: Bool {
        item != nil && !bases.isEmpty && gem != nil
    }
}
