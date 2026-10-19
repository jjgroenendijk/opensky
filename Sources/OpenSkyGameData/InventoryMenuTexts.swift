// The inventory menu's tab names, from the `sAllItems`, `sWeapons`, and other tab string
// settings. See docs/engine/inventory-menu.md.

nonisolated public struct InventoryMenuTexts: Equatable, Sendable {
    /// The tabs in the order the game's menu lists them.
    public enum Tab: CaseIterable, Sendable {
        case favorites, all, weapons, apparel, potions, scrolls, food, ingredients, books, keys
        case misc
    }

    public var labels: [Tab: String] = [
        .favorites: "Favorites", .all: "All", .weapons: "Weapons", .apparel: "Armor",
        .potions: "Potions", .scrolls: "Scrolls", .food: "Food", .ingredients: "Ingredients",
        .books: "Books", .keys: "Keys", .misc: "Misc"
    ]

    public static let vanilla = Self()

    public static let settings: [Tab: String] = [
        .favorites: "sFavorites", .all: "sAllItems", .weapons: "sWeapons", .apparel: "sApparel",
        .potions: "sPotions", .scrolls: "sScrolls", .food: "sFood", .ingredients: "sIngredients",
        .books: "sBooks", .keys: "sKeys", .misc: "sMisc"
    ]

    public init() {}

    public func label(_ tab: Tab) -> String {
        labels[tab] ?? "\(tab)"
    }

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var texts = vanilla
        for (tab, name) in settings {
            if let label = store.text(name).flatMap({ text($0) }) {
                texts.labels[tab] = label
            }
        }
        return texts
    }
}
