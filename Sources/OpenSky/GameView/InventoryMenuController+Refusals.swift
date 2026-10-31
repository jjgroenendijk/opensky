// The inventory actions the game refuses with a notice, through `ItemRefusalRule`.
// See docs/engine/inventory-menu.md#refused-actions.

import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyWorld

extension InventoryMenuController {
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
        facts.canBeFavourite = family.map(Self.favouriteFamilies.contains) ?? true
        facts.isEquipped = game.inventory.use(of: item) == .unequip
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
}
