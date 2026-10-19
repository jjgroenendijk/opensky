// The `itemInfo` object the vanilla item card reads, built from an engine card.

import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyInventoryInterface
@testable import OpenSkyMenus
import Testing

struct InventoryMenuItemCardBridgeTests {
    @Test func aWeaponCardNamesItsPageDamageAndPrice() {
        let card = InventoryItemCard(
            item: FormID(1), layout: .weapon, name: "Iron Sword", kind: "Weapon", value: 25,
            weight: 9, damage: 7
        )
        let info = InventoryMenuMovieBridge.itemCardInfo(card)
        #expect(info["type"] == .integer(2))
        #expect(info["name"] == .string("Iron Sword"))
        #expect(info["damage"] == .integer(7))
        #expect(info["value"] == .integer(25))
        #expect(info["weight"] == .number(9))
        #expect(info["effects"] == .string(""))
    }

    @Test func anIngredientCardLeavesUnknownEffectsToTheMovie() {
        let card = InventoryItemCard(
            item: FormID(2), layout: .ingredient, name: "Wheat", kind: "Ingredient", value: 5,
            weight: 0.1, effects: ["Restore Health", "?", "?", "Fortify Health"]
        )
        let info = InventoryMenuMovieBridge.itemCardInfo(card)
        #expect(info["type"] == .integer(8))
        #expect(info["numItemEffects"] == .integer(4))
        #expect(info["itemEffect0"] == .string("Restore Health"))
        #expect(info["itemEffect1"] == nil)
        #expect(info["itemEffect3"] == .string("Fortify Health"))
    }

    @Test func anArmourCardRoundsTheRatingAndListsTheEnchantment() {
        let card = InventoryItemCard(
            item: FormID(3), layout: .armour, name: "Hide Helmet", kind: "Armour", value: 40,
            weight: 2, armourRating: 12.5, enchantment: "Fortify Archery 10"
        )
        let info = InventoryMenuMovieBridge.itemCardInfo(card)
        #expect(info["type"] == .integer(1))
        #expect(info["armor"] == .integer(13))
        #expect(info["effects"] == .string("Fortify Archery 10"))
    }
}
