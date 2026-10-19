// Tab names from the tab settings, the game's tab order with Favorites and Scrolls,
// and the Food, Keys, Scrolls, and Favorites tabs taking their own rows.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct InventoryMenuTabsTests {
    private func entry(
        _ item: UInt32, _ family: ItemDefinition.Family, isFood: Bool = false,
        isFavourite: Bool = false
    ) -> InventoryMenuEntry {
        InventoryMenuEntry(
            item: FormID(item), name: "\(item)", count: 1, weight: 0, value: 0,
            isEquipped: false, family: family, isFood: isFood, isFavourite: isFavourite
        )
    }

    @Test func tabsTakeTheirNamesFromTheSettings() throws {
        let store = try GameSettingFixture.store([
            "sApparel": .text("APPAREL"),
            "sKeys": .text("KEYS")
        ])
        let texts = InventoryMenuTexts.resolve(store: store) { text in
            guard case let .inline(value) = text.text else { return nil }
            return value
        }
        let labels = InventoryMenuCategory.tabs(texts: texts, favourites: true).map(\.label)
        #expect(labels == [
            "Favorites", "All", "Weapons", "APPAREL", "Potions", "Scrolls", "Food",
            "Ingredients", "Books", "KEYS", "Misc"
        ])
        #expect(InventoryMenuCategory.tabs(texts: texts).first?.label == "All")
    }

    @Test func favouritesTakeMarkedRowsAndTheMenuOpensOnAll() {
        let rows = [
            entry(1, .weapon, isFavourite: true), entry(2, .scroll), entry(3, .weapon)
        ]
        let tabs = InventoryMenuCategory.tabs(texts: .vanilla, favourites: true)
        #expect(rows.filter(tabs[0].accepts).map(\.item.rawValue) == [1])
        #expect(rows.filter { tabs[5].accepts($0) }.map(\.item.rawValue) == [2])
        let model = InventoryMenuModel(
            allEntries: rows, categories: tabs, carriedWeight: 0, gold: 0
        )
        #expect(model.selectedCategoryIndex == 1)
        #expect(model.entries.count == 3)
    }

    @Test func theQuantityStaysBetweenOneAndTheStack() {
        var prompt = InventoryQuantityPrompt(item: FormID(1), name: "Arrow", maximum: 12)
        #expect(prompt.value == 12)
        prompt.adjust(by: 10)
        #expect(prompt.value == 12)
        prompt.adjust(by: -20)
        #expect(prompt.value == 1)
        prompt.adjust(by: 4)
        #expect(prompt.text == "Drop how many Arrow? 5 of 12")
    }

    @Test func onlyAStackAboveTheMovieLimitAsks() {
        #expect(InventoryQuantityPrompt.asking(item: FormID(1), name: "Arrow", count: 5) == nil)
        let prompt = InventoryQuantityPrompt.asking(item: FormID(1), name: "Arrow", count: 6)
        #expect(prompt?.value == 6)
    }

    @Test func foodAndKeysLeaveThePotionAndMiscTabs() {
        let rows = [
            entry(1, .ingestible), entry(2, .ingestible, isFood: true), entry(3, .key),
            entry(4, .miscellaneous)
        ]
        let tabs = InventoryMenuCategory.tabs(texts: .vanilla)
        func items(_ label: String) -> [UInt32] {
            let tab = tabs.first { $0.label == label }
            return rows.filter { tab?.accepts($0) == true }.map(\.item.rawValue)
        }
        #expect(items("Potions") == [1])
        #expect(items("Food") == [2])
        #expect(items("Keys") == [3])
        #expect(items("Misc") == [4])
    }
}
