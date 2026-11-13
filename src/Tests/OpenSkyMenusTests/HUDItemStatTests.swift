import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMenus
import Testing

struct HUDItemStatTests {
    private func card(damage: Int? = nil, rating: Float? = nil) -> InventoryItemCard {
        InventoryItemCard(
            layout: .weapon, name: "Iron Sword", kind: "", value: 25, weight: 9,
            damage: damage, armourRating: rating, effects: [], enchantment: nil,
            isStolen: false, hotkey: nil, isFavourite: false
        )
    }

    @Test func aWeaponShowsDamageAndArmourShowsItsRating() {
        let texts = GameSettingTexts<HUDItemStatText>.vanilla
        #expect(HUDItemStat.of(card(damage: 7), texts: texts) == HUDItemStat(
            value: 7,
            label: "DAMAGE"
        ))
        #expect(
            HUDItemStat.of(card(rating: 25), texts: texts)
                == HUDItemStat(value: 25, label: "ARMOR RATING")
        )
        #expect(HUDItemStat.of(card(), texts: texts) == nil)
        #expect(HUDItemStat.of(nil, texts: texts) == nil)
    }
}
