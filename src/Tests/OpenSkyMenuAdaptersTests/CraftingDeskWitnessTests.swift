// The menu screens reach the crafting desk, the enchanter, and the shout list through
// their ports.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
@testable import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkySessionTesting
import Testing

@MainActor
struct CraftingDeskWitnessTests {
    private let host = MenuHost()

    @Test func theTweenMenuReadsTheLevelAndSendsTheCameraOffset() {
        host.fakeProgression.skillsMenuPlayer = .empty
        let session = FakeGameSessionPort()
        host.gameSession = session
        let screens = MenuScreensWorldAdapter(game: host)
        #expect(screens.tweenLevel.level == 1)
        #expect(!screens.tweenLevel.levelUpReady, "no level waits without leveling")
        screens.setMenuViewOffset(MenuViewOffset(horizontalFOVDegrees: 10))
        #expect(session.menuViewOffsetValue?.horizontalFOVDegrees == 10)
    }

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

    @Test func theCraftingDeskReadsTheSkillBarTheCardAndTheComponents() {
        let screens = MenuScreensWorldAdapter(game: host)
        host.fakeInventory.craftingReadout.craftingSnapshotValue =
            CraftingControlSnapshot(stationName: nil, recipes: [])
        #expect(screens.craftingSkill == nil, "no station is open")
        var recipe = CraftingRecipeReadout(
            id: ResolvedFormID(plugin: "base.esm", objectID: 1), name: "Iron Dagger",
            isEligible: true
        )
        recipe.created = FormID(0x1397E)
        recipe.requirements = "Iron Ingot (3/1)"
        var snapshot = CraftingControlSnapshot(stationName: "Forge", recipes: [recipe])
        snapshot.station = CraftingStationInfo(keywords: [], skill: 10)
        snapshot.description = "Create"
        host.fakeInventory.craftingReadout.craftingSnapshotValue = snapshot
        host.fakeProgression.skillsMenuSkills = [SkillsMenuSkill(
            index: 10, name: "Smithing", description: "", level: 15, progress: 0.5,
            legendaryCount: 0, canMakeLegendary: false
        )]
        #expect(screens.craftingDescription == "Create")
        #expect(screens.craftingSkill == CraftingSkillBar(
            name: "Smithing", level: 15, progress: 0.5
        ))
        #expect(screens.craftingItemCard(FormID(0x1397E)) == nil)
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<CraftingCategoryText>.vanilla
        let row = screens.craftingRecipes.first
        #expect(row?.created == FormID(0x1397E))
        #expect(row?.requirements == "Iron Ingot (3/1)")
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
        let slider = EnchanterSlider(maximum: 30, step: 1, value: 30)
        enchanter.sliderResult = slider
        #expect(screens.enchanter.enchantingSlider(EnchanterSelection()) == slider)
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
        menu.unlockShoutResult = ShoutUnlockReply(text: "Unlocked")
        host.fakeMapWorld.settingTextsResult = GameSettingTexts<ShoutMenuText>.vanilla
        #expect(screens.shoutUnlockStep(at: 0) == nil)
        #expect(screens.shoutUnlockStep(at: MenuScreensGiftListsAdapter.shoutTagBase) == nil)
        #expect(screens.unlockShout(at: MenuScreensGiftListsAdapter.shoutTagBase)
            .text == "Unlocked")
        #expect(screens.giftRefusal(FormID(1), actor: .player, giving: false) == nil)
    }
}
