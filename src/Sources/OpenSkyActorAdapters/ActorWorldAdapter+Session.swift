// `ActorWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import Foundation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
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

extension ActorWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any ActorWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerActorValues(stage: stage)
    }

    private func registerActorValues(stage: SessionStage) {
        let provider = stage.data
        let gameSession = stage.gameSession
        actorList = nil
        // The same test the coordinator makes before it builds its runtime.
        guard provider.actorValueBaselines != nil else { return }
        let settings = provider.gameSettings
        // Chained after the Papyrus VM, so neither unhooks the other. The
        // renderer gates the delta, so a menu-paused frame regenerates nothing.
        gameSession.worldTick.register(.actorValues) { [weak game = self.game] delta in
            game?.actorValues.advance(delta: delta)
        }
        gameSession.frameSteps.register(.actorValues) { [weak self, weak gameSession] _ in
            self?.publishHUDMeters(gameSession: gameSession)
        }
        gameSession.breath = PlayerBreath(settings: BreathSettings.resolve(store: settings))
        gameSession.worldTick.register(.breath) { [weak self, weak gameSession] delta in
            guard let gameSession else { return }
            self?.advanceBreath(delta: delta, gameSession: gameSession)
        }
    }
}
