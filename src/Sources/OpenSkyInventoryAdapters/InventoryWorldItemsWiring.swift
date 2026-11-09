// `InventoryWorldAdapter` joins the started session: what `wireWorldItems` registered.

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
public import OpenSkySessionInterface
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// After the audio and Papyrus subscribers, so the activation sound plays
/// whether or not the take succeeds. The crime reporter joins the take path.
public struct InventoryWorldItemsWiring {
    public init(_ adapter: InventoryWorldAdapter, streamer: any CellStreamerPort) {
        streamer.onInteraction.register(.worldItems) { [weak adapter] event in
            guard let adapter else { return }
            let action = event.target.interaction.action
            if action == .take, adapter.openBook(event.target.interaction) {
                return
            }
            if event.target.interaction.isBed {
                // An inmate's bed asks to serve the sentence (UESP "Skyrim:Crime").
                if adapter.game.crime.jailStay != nil {
                    adapter.askToServeSentence()
                    return
                }
                adapter.game.menuScreens.sleepWait.open(
                    sleeping: true, bed: event.target.interaction.reference
                )
                return
            }
            if adapter.useFurniture(event.target.interaction) {
                return
            }
            adapter.run(adapter.game.inventory.handleInteraction(action))
            if action == .use, adapter.game.inventory.isCrafting {
                adapter.game.menuScreens.crafting.open()
            }
        }
    }
}
