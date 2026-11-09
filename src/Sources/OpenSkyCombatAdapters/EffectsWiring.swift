// `EffectsWorldAdapter` joins the started session: what `wireEffects` registered.

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Connects `EffectsWorldAdapter` to the started session.
public struct EffectsWiring {
    public init(
        _ adapter: EffectsWorldAdapter,
        provider: WorldDataStores,
        streamer: CellStreamer,
        gameSession: GameSession
    ) {
        guard let records = provider.effectRecords else { return }
        gameSession.imageSpaceLinks = ImageSpaceLinks(
            records: records, weatherPlugin: EffectsWorldAdapter.basePlugin
        )
        adapter.game.effects.applyGraphicsSettings(adapter.game.playerSettings.store)
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.effects) { [weak adapter, weak gameSession, weak streamer] position in
            guard let adapter, let gameSession else { return }
            adapter.state.cameraPosition = position
            adapter.tick(gameSession: gameSession, streamer: streamer)
            let now = ProcessInfo.processInfo.systemUptime
            let delta = Float(now - (adapter.state.lastImpulseStep ?? now))
            adapter.state.lastImpulseStep = now
            if gameSession.movementMode.isPlayerControlled {
                adapter.game.combat.impulses?.advance(deltaTime: delta)
            }
        }
    }
}
