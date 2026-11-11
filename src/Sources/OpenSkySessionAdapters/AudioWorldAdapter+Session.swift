// `AudioWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension AudioWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some AudioWorldHosts,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerAudioCallbacks(stage: stage)
    }

    private func registerAudioCallbacks(stage: SessionStage) {
        let streamer = stage.streamer
        streamer.onInteraction.register(.audio) { [weak game = self.game] event in
            game?.audio.soundDirector?.handleInteraction(event)
        }
        streamer.onInteractionAnimation = { [weak game = self.game] event in
            game?.audio.soundDirector?.handleInteractionAnimation(event)
        }
        streamer.onAmbienceContextChanged = { [weak game = self.game] context in
            game?.audio.soundDirector?.handleAmbienceContext(context)
        }
        streamer.onMusicContextChanged = { [weak game = self.game] context in
            game?.audio.musicDirector?.handleMusicContext(context)
        }
        streamer.musicFeed.locationMusicType = { [weak game = self.game] scene in
            game?.runtimeStateWorld.locationMusicType(of: scene.locationKey)
        }
    }
}
