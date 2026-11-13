// The inventory actions the game refuses with a notice, through `ItemRefusalRule`.
// See docs/engine/inventory-menu.md#refused-actions.

import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkySessionInterface
import OpenSkyWorld

extension InventoryMenuController {
    var itemActions: InventoryItemActions {
        InventoryItemActions(game: game)
    }
}

/// Uses and refuses the inventory menu's items. It holds the host, not the menu.
struct InventoryItemActions {
    let game: any InventoryMenuHost

    /// The refusal notice of `request` on `item`, shown on the HUD, or nil to go on.
    func refusal(_ request: ItemRequest, of item: FormID) -> String? {
        guard let text = ItemRefusalRule.refusal(request, facts(for: item)) else { return nil }
        let notice = game.mapWorld.settingTexts(ItemRefusalText.self)[text]
        game.hud.showNotification(notice)
        return notice
    }

    func request(for use: ItemUse, item: FormID) -> ItemRequest {
        switch use {
        case .applyPoison, .consume: .consume
        case .unequip: .unequip
        case .equip:
            .equip(isArmour: definition(of: item)?.family == .armor)
        }
    }

    private func facts(for item: FormID) -> ItemRequestFacts {
        var facts = ItemRequestFacts()
        let family = definition(of: item)?.family
        facts.isKey = family == .key
        facts.isQuestItem = game.inventory.scriptItems.isQuestItem(item)
        facts.canBeFavourite = family.map(Self.favouriteFamilies.contains) ?? true
        facts.isEquipped = game.inventory.consumables.use(of: item) == .unequip
        facts.playerIsAttacking = game.combat.playerActionFacts?.attackState.isAttacking == true
        let status = game.gameSession?.locomotion.status
        facts.playerIsAirborne = status.map { !$0.isGrounded } ?? false
        facts.hasDropRoom = game.inventoryWorld.dropPlacement() != nil
        return facts
    }

    private func definition(of item: FormID) -> ItemDefinition? {
        game.inventory.runtime?.inventory.baselines.items.definition(item)
    }

    /// Spells and shouts are marked in the magic menu.
    private static let favouriteFamilies: Set<ItemDefinition.Family> = [
        .armor, .ammunition, .ingestible, .ingredient, .scroll, .weapon
    ]

    func use(_ item: FormID) -> String {
        let inventory = game.inventory
        let use = inventory.consumables.use(of: item)
        if let refused = refusal(request(for: use, item: item), of: item) {
            return refused
        }
        switch use {
        case .applyPoison: return inventory.consumables.applyPoison(item)
            .text(game.mapWorld.settingTexts())
        case .consume: return game.magic.itemUse.consumeMagicItem(item).text
        case .unequip:
            return game.inventoryWorld.run(inventory.equipmentChanges.unequipItem(
                item,
                on: .player
            ))
            .text
        case .equip:
            return game.inventoryWorld.run(inventory.equipmentChanges.equipItem(item, on: .player))
                .text
        }
    }
}
