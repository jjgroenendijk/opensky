// What the inventory menu shows and asks about the selected item: its card and charge, the
// question before a poison goes on a weapon, and the Charge button's list of filled soul
// gems. See docs/engine/inventory-menu.md#recharging.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkySessionInterface

extension InventoryMenuController {
    func showSoulGems() {
        lastActionText = itemDetails.showSoulGems(for: model.selectedEntry?.item, on: movie)
    }

    func chooseSoulGem(_ index: Int) {
        if itemDetails.recharge(model.selectedEntry?.item, gemIndex: index) {
            lastActionText = "Recharged."
        }
        refreshModel()
    }
}

struct InventoryMenuItemDetails {
    unowned let game: any InventoryMenuHost
    let messages: any MessageCoordinatorPort

    var menuTexts: InventoryMenuTexts {
        game.inventory.itemCards.menuTexts
    }

    func card(for item: FormID?) -> InventoryItemCard? {
        item.flatMap { game.inventory.itemCards.itemCard(for: $0) }
    }

    func chargePercent(of item: FormID?) -> Float? {
        item.flatMap { game.magic.weaponEnchantments.chargePercent(of: $0) }
    }

    /// The question asked before `item` goes on a weapon; nil when it is no poison or the
    /// player cannot use it now.
    func poisonQuestion(_ item: FormID, refusal: String?) -> String? {
        let consumables = game.inventory.consumables
        guard consumables.use(of: item) == .applyPoison, refusal == nil else { return nil }
        return consumables.poisonQuestion(item, texts: game.mapWorld.settingTexts())
    }

    /// Asks `question` with Yes and No; `answer` gets true for Yes.
    func ask(_ question: String, answer: @escaping @MainActor (Bool) -> Void) {
        let words = game.mapWorld.settingTexts(MessageBoxText.self)
        messages.presentChoices(
            title: nil, text: question, buttons: [words[.yes], words[.no]]
        ) { choice in
            answer(choice == 0)
        }
    }

    /// Shows the filled gems that could charge `item`, or the notice that none can, and
    /// returns the text the menu reports.
    func showSoulGems(for item: FormID?, on movie: MenuMovieSession) -> String {
        let texts = game.mapWorld.settingTexts(RechargeText.self)
        guard
            let item,
            let offer = game.magic.weaponEnchantments.rechargeOffer(for: item),
            !offer.gems.isEmpty
        else {
            game.hud.showNotification(texts[.noChargeItems])
            return texts[.noChargeItems]
        }
        movie.publish {
            InventoryMenuMovieBridge.publishSoulGemList(
                offer, title: texts[.chooseSoulGem], runtime: $0
            )
        }
        return texts[.chooseSoulGem]
    }

    func recharge(_ item: FormID?, gemIndex: Int) -> Bool {
        guard let item else { return false }
        return game.magic.weaponEnchantments.recharge(item, gemIndex: gemIndex)
    }
}
