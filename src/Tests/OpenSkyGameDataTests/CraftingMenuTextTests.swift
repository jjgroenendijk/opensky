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

    @Test func eachStationHasItsTitleAndDescription() {
        let forge = CraftingStationInfo(keywords: [], skill: nil)
        #expect(CraftingMenuText.title(station: forge, name: "Forge", texts: .vanilla) == "Forge")
        let grindstone = CraftingStationInfo(keywords: [], skill: nil, improves: true)
        let armour = CraftingStationInfo(
            keywords: [], skill: nil, improves: true, improvesArmor: true
        )
        let lab = CraftingStationInfo(keywords: [], skill: nil, brews: true)
        let texts = GameSettingTexts<CraftingMenuText>.vanilla
        #expect(CraftingMenuText.title(station: grindstone, name: "", texts: texts)
            == texts[.weaponSmithing])
        #expect(CraftingMenuText.title(station: armour, name: "", texts: texts)
            == texts[.armorSmithing])
        #expect(CraftingMenuText.title(station: lab, name: "", texts: texts) == texts[.alchemy])
        #expect(CraftingMenuText.description(station: forge, texts: texts)
            == texts[.constructibleDescription])
        #expect(CraftingMenuText.description(station: armour, texts: texts)
            == texts[.smithingDescription])
        #expect(CraftingMenuText.description(station: lab, texts: texts)
            == texts[.alchemyDescription])
    }
}
