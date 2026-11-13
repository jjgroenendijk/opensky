// The arcane enchanter's half of the crafting menu. See docs/engine/enchanting.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkySessionInterface

/// Part of `MenuScreensWorldAdapter`, over the crafting desk's host.
struct MenuScreensEnchanterAdapter {
    let game: any MenuScreensCraftingDeskHost
}

extension MenuScreensEnchanterAdapter: CraftingMenuEnchanter {
    var enchanterChoices: EnchanterChoices? {
        guard game.inventory.craftingReadout.craftingSnapshot.station?.enchants == true else {
            return nil
        }
        return game.magic.enchanter.enchanterChoices
    }

    var enchantingTexts: GameSettingTexts<EnchantingMenuText> {
        game.mapWorld.settingTexts()
    }

    func disenchant(_ item: FormID) -> EnchanterAnswer {
        game.magic.enchanter.disenchant(item)
    }

    func enchantRefusal(_ selection: EnchanterSelection) -> String? {
        game.magic.enchanter.refusal(of: selection)
    }

    func enchant(_ selection: EnchanterSelection) -> EnchanterAnswer {
        game.magic.enchanter.enchant(selection)
    }
}
