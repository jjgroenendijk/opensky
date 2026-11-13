import OpenSkyGameData
import Testing

struct CraftingMenuTextTests {
    @Test func anEnchanterIsTitledWithTheEnchantingTexts() {
        var station = CraftingStationInfo(keywords: [], skill: nil)
        station.enchants = true
        let header = CraftingMenuText.header(
            station: station,
            name: "Arcane Enchanter",
            texts: .vanilla
        )
        #expect(header.hasPrefix("Enchanting: Choose an item to destroy"))
    }
}
