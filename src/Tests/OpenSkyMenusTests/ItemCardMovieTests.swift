// The crafting bar and the inventory item card through their movie calls, on an empty
// movie that logs what the bridges send.

import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMagicInterface
@testable import OpenSkyMenus
import Testing

@MainActor
struct ItemCardMovieTests {
    @Test func theItemCardIsSentAndAnEmptyRowHidesIt() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let callback = InventoryMenuMovieBridge.itemCardCallback
        let log = MenuMovieCallLog(runtime: runtime, names: [callback])
        InventoryMenuMovieBridge.publishItemCard(nil, charge: 50, runtime: runtime)
        let offer = RechargeOffer(
            currentPercent: 20, gems: [RechargeOffer.Gem(name: "Petty Soul Gem", addedPercent: 10)]
        )
        InventoryMenuMovieBridge.publishSoulGemList(offer, title: "Recharge", runtime: runtime)
        #expect(log.names == [callback, callback])
    }

    @Test func theCraftingBarGetsItsLabelsAndTheCraftSwitch() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let buttons = CraftingMenuButtons.make(
            .init(mode: .create, hasRow: true), texts: GameSettingTexts<CraftingButtonText>.vanilla
        )
        CraftingMenuMovieBridge.activate(station: "Forge", buttons: buttons, runtime: runtime)
        CraftingMenuMovieBridge.publish(buttons, runtime: runtime)
        #expect(buttons.labels.first == "Create")
    }
}
