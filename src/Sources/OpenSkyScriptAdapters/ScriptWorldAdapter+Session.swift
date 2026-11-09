// `ScriptWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWeather
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension ScriptWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some ScriptWorldHost & ScriptActorBindingsHost & ScriptPerkBindingsHost &
            ScriptSessionBindingsHost & ScriptPlayerBindingsHost & ScriptReferenceBindingsHost &
            ScriptSoundBindingsHost & ScriptPhysicsBindingsHost & ScriptNodeBindingsHost &
            ScriptSkyBindingsHost & ScriptFeatureBindingsHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerScripts(stage: stage)
    }

    private func registerScripts(stage: SessionStage) {
        guard stage.data.scriptFileSystem != nil else { return }
        let gameSession = stage.gameSession
        let streamer = stage.streamer
        let resolver = stage.data.scriptFormIDResolver
        streamer.onInteraction.register(.scripts) { [weak self] event in
            guard let self, let bridge = state.bridge else { return }
            bridge.handleInteraction(event)
            searchAshPileOwner(of: event, bridge: bridge)
        }
        // The streamer tests trigger volumes once per walk-mode frame; each edge
        // queues one event per script on the volume's reference.
        streamer.onTriggerTransition.register(.scripts) { [weak self] event in
            self?.state.bridge?.handleTriggerTransition(event)
        }
        streamer.onCellAttached.register(.scripts) { [weak self] attachment in
            guard let world = self?.state.bridge?.world, let location = attachment.scene.location
            else { return }
            world.attach(
                cell: location,
                references: attachment.scene.references,
                formIDResolver: resolver,
                firstIntegration: attachment.isFirstIntegration
            )
        }
        streamer.onCellDetached.register(.scripts) { [weak self] location in
            self?.state.bridge?.world?.detach(cell: location)
        }
        gameSession.worldTick.register(.scripts) { [weak self, weak gameSession] delta in
            self?.soundBindings.answerSoundWaits()
            self?.nodeBindings.answerPathWaits()
            self?.game.scripts.advance(delta: delta)
            let menuTime = gameSession?.consumeMenuTime() ?? 0
            if menuTime > 0 {
                self?.game.scripts.advanceMenuTime(delta: menuTime)
            }
        }
    }
}
