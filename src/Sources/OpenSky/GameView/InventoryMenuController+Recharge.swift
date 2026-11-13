// The Charge button: the item card turns into the list of filled soul gems, and a press
// on one recharges the selected weapon. See docs/engine/inventory-menu.md#recharging.

import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkySessionInterface

extension InventoryMenuController {
    func showSoulGems() {
        let texts = game.mapWorld.settingTexts(RechargeText.self)
        guard
            let item = model.selectedEntry?.item,
            let offer = game.magic.weaponEnchantments.rechargeOffer(for: item),
            !offer.gems.isEmpty
        else {
            lastActionText = texts[.noChargeItems]
            game.hud.showNotification(texts[.noChargeItems])
            return
        }
        movie.publish {
            InventoryMenuMovieBridge.publishSoulGemList(
                offer, title: texts[.chooseSoulGem], runtime: $0
            )
        }
        lastActionText = texts[.chooseSoulGem]
    }

    func chooseSoulGem(_ index: Int) {
        guard let item = model.selectedEntry?.item else { return }
        if game.magic.weaponEnchantments.recharge(item, gemIndex: index) {
            lastActionText = "Recharged."
        }
        refreshModel()
    }
}
