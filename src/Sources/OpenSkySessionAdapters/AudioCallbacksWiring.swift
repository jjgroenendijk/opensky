// `AudioWorldAdapter` joins the started session: what `wireAudioCallbacks` registered.

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

/// Each callback does nothing until audio is enabled. The activation sound
/// plays in the first interaction step, before Papyrus `OnActivate`.
public struct AudioCallbacksWiring {
    public init(_ adapter: AudioWorldAdapter, _ streamer: CellStreamer) {
        let audio = adapter.game.audio
        streamer.onInteraction.register(.audio) { [weak audio] event in
            audio?.soundDirector?.handleInteraction(event)
        }
        streamer.onInteractionAnimation = { [weak audio] event in
            audio?.soundDirector?.handleInteractionAnimation(event)
        }
        streamer.onAmbienceContextChanged = { [weak audio] context in
            audio?.soundDirector?.handleAmbienceContext(context)
        }
        streamer.onMusicContextChanged = { [weak audio] context in
            audio?.musicDirector?.handleMusicContext(context)
        }
        streamer.musicFeed.locationMusicType = { [weak game = adapter.game] scene in
            game?.runtimeStateWorld.locationMusicType(of: scene.locationKey)
        }
    }
}
