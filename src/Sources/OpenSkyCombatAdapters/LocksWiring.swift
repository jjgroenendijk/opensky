// `LockWorldAdapter` joins the started session: what `wireLocks` registered.

import Foundation
import OpenSkyActors
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// After `wireWorldItems`, which builds the lock coordinator.
public struct LocksWiring {
    public init(_ adapter: LockWorldAdapter, streamer: CellStreamer, gameSession: GameSession) {
        let renderer = gameSession.renderer
        let locks = adapter.game.inventory.locks
        let inventoryWorld = adapter.game.inventoryWorld
        streamer.activationGate.register(.lock) { [weak locks, weak inventoryWorld] target in
            locks.flatMap { inventoryWorld?.run($0.gate(target)) }
        }
        let menu = adapter.game.lockpickingMenu
        streamer.activationGate.refusals.register(.lockpicking) { [weak menu] refusal in
            menu?.handle(refusal)
        }
        // Frame steps run while the menu pauses the world; the menu keeps its own clock.
        gameSession.frameSteps.register(.lockpicking) { [weak menu] _ in
            menu?.tick(now: Date())
        }
        renderer.worldOverlaySources
            .register(identifier: "lock-selection") { [weak locks] _, list in
                guard let position = locks?.selectedInteraction?.position else { return }
                list.addMarker(
                    at: position,
                    size: LockWorldAdapter.markerSize,
                    color: WorldOverlayMarkerColour.lock
                )
            }
    }
}
