// The crafting menu's header: the station's purpose in the game's words.
// See docs/engine/crafting.md#crafting-menu.

import Foundation

nonisolated public enum CraftingMenuText: String, GameSettingTextKey {
    case constructibleDescription = "sConstructibleMenuDescription"
    case armorSmithing = "sArmorSmithing"
    case weaponSmithing = "sWeaponSmithing"
    case smithingDescription = "sSmithingMenuDescription"
    case alchemy = "sAlchemy"
    case alchemyDescription = "sAlchemyMenuDescription"
    case enchanting = "sEnchanting"
    case enchantingDescription = "sEnchantMenuDescription"

    public var fallback: String {
        switch self {
        case .constructibleDescription: "Create"
        case .armorSmithing: "Armor Smithing"
        case .weaponSmithing: "Weapon Smithing"
        case .smithingDescription: "Improve"
        case .alchemy: "Alchemy"
        case .alchemyDescription: "Combine Ingredients"
        case .enchanting: "Enchanting"
        case .enchantingDescription:
            "Choose an item to destroy and learn its Enchantment, or combine an Item, "
                + "Enchantment, and Soul Gem to create magic items"
        }
    }

    /// `<station>: <sConstructibleMenuDescription>` at a forge, the smithing title of
    /// the bench at a grindstone or armour table, and the alchemy or enchanting title.
    public static func header(
        station: CraftingStationInfo, name: String, texts: GameSettingTexts<Self>
    ) -> String {
        if station.brews {
            return "\(texts[.alchemy]): \(texts[.alchemyDescription])"
        }
        if station.enchants {
            return "\(texts[.enchanting]): \(texts[.enchantingDescription])"
        }
        if station.improves {
            let title = texts[station.improvesArmor ? .armorSmithing : .weaponSmithing]
            return "\(title): \(texts[.smithingDescription])"
        }
        return "\(name): \(texts[.constructibleDescription])"
    }
}
