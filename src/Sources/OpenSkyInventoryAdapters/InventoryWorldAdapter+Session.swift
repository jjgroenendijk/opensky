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
        game: some InventoryWorldHosts,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        interactions.registerInventoryWorldItems(stage: stage)
    }
}

/// What the use key does on a placed item, bed, chair, or book, before the inventory rules.
final class InventoryInteractions {
    let hosts: any InventoryWorldHosts

    init(hosts: any InventoryWorldHosts) {
        self.hosts = hosts
    }

    var game: any InventoryWorldHost {
        hosts
    }

    var crosshairInteraction: PlacedInteraction? {
        game.hud.interactionTarget?.interaction
    }

    func isBook(_ base: FormID) -> Bool {
        game.menuScreens.book.isBook(base)
    }

    func registerInventoryWorldItems(stage: SessionStage) {
        let streamer = stage.streamer
        streamer.events.onInteraction.register(.worldItems) { [weak self] event in
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
            InventoryCommandRunner(game: hosts)
                .run(game.inventory.itemActions.handleInteraction(action))
            if action == .use, game.inventory.isCrafting {
                game.menuScreens.crafting.open()
            }
        }
    }

    func askToServeSentence() {
        let words = game.mapWorld.settingTexts(MessageBoxText.self)
        game.messages.presentChoices(
            title: nil, text: game.crime.crimeTexts.serveSentenceQuestion,
            buttons: [words[.yes], words[.no]]
        ) { [weak self] answer in
            guard answer == 0, let self else { return }
            game.crime.serveSentence()
        }
    }

    /// A chair or a bench seats the player. A crafting station keeps its menu, and a bed
    /// its rest menu. False while the furniture switch is off.
    func useFurniture(_ interaction: PlacedInteraction) -> Bool {
        guard
            !interaction.seats.isEmpty,
            (interaction.station?.workbench.benchType ?? WorkbenchType.none) == WorkbenchType.none,
            let key = game.streamer.referenceEntry(formID: interaction.reference)?.key
        else { return false }
        if case .failure(.disabled) = game.furniture.use(key, by: .player) {
            return false
        }
        return true
    }

    /// A book is read where it lies, as in the game; its bar offers to take it.
    func openBook(_ interaction: PlacedInteraction) -> Bool {
        let book = game.menuScreens.book
        guard book.isBook(interaction.base), let runtime = game.inventory.runtime else {
            return false
        }
        let offer = BookTakeOffer(
            isTheft: runtime.isTheft(interaction), reference: interaction.reference
        ) { [game] in
            game.inventory.itemActions.take(interaction)
        }
        return book.open(item: interaction.base, takeOffer: offer)
    }
}
