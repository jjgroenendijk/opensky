// The `itemInfo` object the vanilla item card reads, built from an engine card.

import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyInventoryInterface
@testable import OpenSkyMenus
import Testing

struct InventoryMenuItemCardBridgeTests {
    /// A row's card is its item's card; a row for one copy shows that copy's name and
    /// value, and no row shows no card.
    @Test func aRowsCardTakesTheCopysNameAndValue() {
        let sword = InventoryItemCard(
            layout: .weapon, name: "Iron Sword", kind: "Weapon", value: 25, weight: 9
        )
        var entry = InventoryMenuEntry(
            item: FormID(0x10), name: "Biter", count: 1, weight: 9, value: 633,
            isEquipped: false, family: nil
        )
        let lookup: (FormID) -> InventoryItemCard? = { $0 == FormID(0x10) ? sword : nil }
        #expect(InventoryMenuMovieBridge.card(for: entry, lookup: lookup)?.name == "Iron Sword")
        entry.copy = ItemCopy(enchantment: FormID(0xFF00_0800))
        let copy = InventoryMenuMovieBridge.card(for: entry, lookup: lookup)
        #expect(copy?.name == "Biter")
        #expect(copy?.value == 633)
        #expect(InventoryMenuMovieBridge.card(for: nil, lookup: lookup) == nil)
    }

    @Test func aWeaponCardNamesItsPageDamageAndPrice() {
        let card = InventoryItemCard(
            layout: .weapon,
            name: "Iron Sword",
            kind: "Weapon",
            value: 25,
            weight: 9,
            damage: 7
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
            layout: .ingredient,
            name: "Wheat",
            kind: "Ingredient",
            value: 5,
            weight: 0.1,
            effects: ["Restore Health", "?", "?", "Fortify Health"]
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
            layout: .armour,
            name: "Hide Helmet",
            kind: "Armour",
            value: 40,
            weight: 2,
            armourRating: 12.5,
            enchantment: "Fortify Archery 10"
        )
        let info = InventoryMenuMovieBridge.itemCardInfo(card)
        #expect(info["type"] == .integer(1))
        #expect(info["armor"] == .integer(13))
        #expect(info["effects"] == .string("Fortify Archery 10"))
    }

    @Test func theChargeButtonAndTheGemListReachTheEngine() {
        #expect(InventoryMenuMovieBridge
            .action(named: "ShowSoulGemList", arguments: []) == .showSoulGems)
        #expect(
            InventoryMenuMovieBridge.action(named: "ItemCardListCallback", arguments: [.number(2)])
                == .chooseCardListEntry(index: 2)
        )
    }
}
