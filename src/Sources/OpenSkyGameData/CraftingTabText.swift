// The crafting menu's tab titles at an improve bench and an alchemy lab.
// See docs/engine/crafting.md#crafting-menu.

nonisolated public enum CraftingTabText: String, GameSettingTextKey {
    /// The one tab of an armour table.
    case armor = "sArmor"
    /// The one tab of a grindstone.
    case weapons = "sWeapons"
    case ingredients = "sIngredients"

    public var fallback: String {
        switch self {
        case .armor: "ARMOR"
        case .weapons: "WEAPONS"
        case .ingredients: "INGREDIENTS"
        }
    }
}
