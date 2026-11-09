// `LockWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

extension LockWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any LockWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerLocks(stage: stage)
    }

    private func registerLocks(stage: SessionStage) {
        let streamer = stage.streamer
        let gameSession = stage.gameSession
        let renderer = gameSession.renderer
        streamer.activationGate.register(.lock) { [weak game = self.game] target in
            guard let game else { return nil }
            return game.inventoryWorld.run(game.inventory.locks.gate(target))
        }
        streamer.activationGate.refusals.register(.lockpicking) { [weak game = self.game] refusal in
            game?.lockpickingMenu.handle(refusal)
        }
        // Frame steps run while the menu pauses the world; the menu keeps its own clock.
        gameSession.frameSteps.register(.lockpicking) { [weak game = self.game] _ in
            game?.lockpickingMenu.tick(now: Date())
        }
        renderer.worldOverlaySources
            .register(identifier: "lock-selection") { [weak game = self.game] _, list in
                guard let position = game?.inventory.locks.selectedInteraction?.position
                else { return }
                list.addMarker(
                    at: position,
                    size: LockWorldAdapter.markerSize,
                    color: WorldOverlayMarkerColour.lock
                )
            }
    }
}
