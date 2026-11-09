// `ScriptWorldAdapter` joins the started session: what `wireScripts` registered.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWeather
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The VM's cell, trigger, and frame events.
public struct ScriptsWiring {
    public init(
        _ adapter: ScriptWorldAdapter,
        _ scripts: ScriptCoordinator,
        resolver: FormIDResolver,
        gameSession: GameSession,
        streamer: CellStreamer
    ) {
        let bridge = scripts.bridge
        let world = scripts.runtime
        streamer.onInteraction.register(.scripts) { [weak adapter, weak bridge] event in
            guard let bridge else { return }
            bridge.handleInteraction(event)
            adapter?.searchAshPileOwner(of: event, bridge: bridge)
        }
        // The streamer tests trigger volumes once per walk-mode frame; each edge
        // queues one event per script on the volume's reference.
        streamer.onTriggerTransition.register(.scripts) { [weak bridge] event in
            bridge?.handleTriggerTransition(event)
        }
        scripts.startQuestScripts()
        streamer.onCellAttached.register(.scripts) { [weak world] attachment in
            guard let world, let location = attachment.scene.location else { return }
            world.attach(
                cell: location,
                references: attachment.scene.references,
                formIDResolver: resolver,
                firstIntegration: attachment.isFirstIntegration
            )
        }
        streamer.onCellDetached.register(.scripts) { [weak world] location in
            world?.detach(cell: location)
        }
        gameSession.worldTick.register(.scripts) { [weak adapter, weak gameSession] delta in
            adapter?.soundBindings.answerSoundWaits()
            adapter?.nodeBindings.answerPathWaits()
            adapter?.game.scripts.advance(delta: delta)
            let menuTime = gameSession?.consumeMenuTime() ?? 0
            if menuTime > 0 {
                adapter?.game.scripts.advanceMenuTime(delta: menuTime)
            }
        }
    }
}
