// The menu screens reach the crafting desk, the enchanter, and the shout list through
// their ports.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
@testable import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct CraftingDeskWitnessTests {
    private let host = MenuHost()

    @Test func theCraftingDeskReadsTheOpenStationAndItsTexts() {
        let screens = MenuScreensWorldAdapter(game: host)
        let readout = host.fakeInventory.craftingReadout
        var snapshot = CraftingControlSnapshot(stationName: "Forge", recipes: [])
        snapshot.station = CraftingStationInfo(keywords: [], skill: nil)
        readout.craftingSnapshotValue = snapshot
        #expect(screens.craftingStation != nil)
        #expect(screens.enchanter.enchanterChoices == nil)
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<CraftingButtonText>.vanilla
        #expect(screens.craftingButtonTexts == .vanilla)
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<CraftingTabText>.vanilla
        #expect(screens.craftingTabTexts == .vanilla)
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<EnchantingMenuText>.vanilla
        #expect(screens.enchanter.enchantingTexts == .vanilla)
    }

    @Test func theEnchanterCallsReachTheMagicPort() {
        let screens = MenuScreensWorldAdapter(game: host)
        let enchanter = host.fakeMagic.enchanter
        let answer = EnchanterAnswer(text: "Learned", done: true)
        enchanter.disenchantResult = answer
        enchanter.enchantResult = answer
        enchanter.refusalResult = "Choose"
        #expect(screens.enchanter.disenchant(FormID(1)) == answer)
        #expect(screens.enchanter.enchant(EnchanterSelection()) == answer)
        #expect(screens.enchanter.enchantRefusal(EnchanterSelection()) == "Choose")
        let readout = host.fakeInventory.craftingReadout
        var snapshot = CraftingControlSnapshot(stationName: "Enchanter", recipes: [])
        var station = CraftingStationInfo(keywords: [], skill: nil)
        station.enchants = true
        snapshot.station = station
        readout.craftingSnapshotValue = snapshot
        enchanter.enchanterChoicesValue = EnchanterChoices()
        #expect(screens.enchanter.enchanterChoices == EnchanterChoices())
    }

    @Test func questionsAndNoticesGoToTheMessageBox() {
        let screens = MenuScreensWorldAdapter(game: host)
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<MessageBoxText>.vanilla
        screens.confirm("Destroy it?") { _ in }
        screens.inform("Learned")
        #expect(host.fakeMessages.presentChoicesCalls.map(\.text) == ["Destroy it?", "Learned"])
    }

    @Test func shoutRowsReachTheShoutList() {
        let screens = MenuScreensWorldAdapter(game: host)
        let menu = host.fakeMagic.magicMenu
        menu.unlockShoutResult = "Unlocked"
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<ShoutMenuText>.vanilla
        #expect(screens.shoutUnlockStep(at: 0) == nil)
        #expect(screens.shoutUnlockStep(at: MenuScreensGiftListsAdapter.shoutTagBase) == nil)
        #expect(screens.unlockShout(at: MenuScreensGiftListsAdapter.shoutTagBase) == "Unlocked")
        #expect(screens.giftRefusal(FormID(1), actor: .player, giving: false) == nil)
    }
}
