// `ActorWorldAdapter` joins the started session: what `wireActorValues` registered.

import Foundation
import OpenSkyActors
import OpenSkyActorsInterface
public import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Connects `ActorWorldAdapter` to the started session.
public struct ActorValuesWiring {
    public init(_ adapter: ActorWorldAdapter, provider: WorldDataStores, gameSession: GameSession) {
        adapter.baseNames = [:]
        adapter.referenceNames = nil
        adapter.actorList = nil
        let coordinator = adapter.game.actorValues
        guard coordinator.runtime != nil else { return }
        let settings = provider.gameSettings
        // Chained after the Papyrus VM, so neither unhooks the other. The
        // renderer gates the delta, so a menu-paused frame regenerates nothing.
        gameSession.worldTick.register(.actorValues) { [weak coordinator] delta in
            coordinator?.advance(delta: delta)
        }
        gameSession.frameSteps.register(.actorValues) { [weak adapter, weak gameSession] _ in
            adapter?.publishHUDMeters(gameSession: gameSession)
        }
        gameSession.breath = PlayerBreath(settings: BreathSettings.resolve(store: settings))
        gameSession.worldTick.register(.breath) { [weak adapter, weak gameSession] delta in
            guard let gameSession else { return }
            adapter?.advanceBreath(delta: delta, gameSession: gameSession)
        }
    }
}
