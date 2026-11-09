// `InventoryWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

extension InventoryWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some InventoryWorldHost & InventoryReadoutsHost & InventoryPickpocketHost &
            InventoryPerksHost & InventoryRecipesHost & InventoryVendorHost & InventoryCommandsHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerInventoryWorldItems(stage: stage)
    }

    private func registerInventoryWorldItems(stage: SessionStage) {
        let streamer = stage.streamer
        streamer.onInteraction.register(.worldItems) { [weak self] event in
            guard let self else { return }
            let action = event.target.interaction.action
            if action == .take, openBook(event.target.interaction) {
                return
            }
            if event.target.interaction.isBed {
                // An inmate's bed asks to serve the sentence (UESP "Skyrim:Crime").
                if game.crime.jailStay != nil {
                    askToServeSentence()
                    return
                }
                game.menuScreens.sleepWait.open(
                    sleeping: true, bed: event.target.interaction.reference
                )
                return
            }
            if useFurniture(event.target.interaction) {
                return
            }
            run(game.inventory.handleInteraction(action))
            if action == .use, game.inventory.isCrafting {
                game.menuScreens.crafting.open()
            }
        }
    }
}
