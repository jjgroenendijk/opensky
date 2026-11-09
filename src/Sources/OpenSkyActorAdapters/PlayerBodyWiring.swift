// `PlayerWorldAdapter` joins the started session: what `wirePlayerBody` registered.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The graph and the body outlive every cell, so this is not streaming.
public struct PlayerBodyWiring {
    public init(_ adapter: PlayerWorldAdapter, gameSession: GameSession) {
        let player = adapter.game.player
        player.requestBody()
        gameSession.assetDrains.register(.playerBody) { [weak player] _ in
            player?.drainClipLoads()
        }
        gameSession.frameSteps.register(.playerBody) { [weak player] _ in
            player?.refreshBody()
        }
    }
}
