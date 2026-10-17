// Tab names from the tab settings, and the Food and Keys tabs taking their own rows.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct InventoryMenuTabsTests {
    private func entry(
        _ item: UInt32, _ family: ItemDefinition.Family, isFood: Bool = false
    ) -> InventoryMenuEntry {
        InventoryMenuEntry(
            item: FormID(item), name: "\(item)", count: 1, weight: 0, value: 0,
            isEquipped: false, family: family, isFood: isFood
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
        let labels = InventoryMenuCategory.tabs(texts: texts).map(\.label)
        #expect(labels == [
            "All", "Weapons", "APPAREL", "Potions", "Food", "Ingredients", "Books", "KEYS", "Misc"
        ])
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
