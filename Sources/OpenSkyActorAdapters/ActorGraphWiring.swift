// `ActorGraphWorldAdapter` joins the started session: what `wire` registered.

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// After the idles, so an idle event raised this frame reaches the graph's step.
public struct ActorGraphWiring {
    public init(_ adapter: ActorGraphWorldAdapter, gameSession: GameSession) {
        guard adapter.game.audioFileSystem != nil else { return }
        let store = adapter.game.playerSettingsStore
        adapter.graphs.load(settings: store)
        // The launcher page writes the same settings while a session runs.
        store.observe { [weak adapter, weak store] id in
            guard let store, ActorGraphWorldAdapter.settings.contains(id) else { return }
            adapter?.graphs.load(settings: store)
        }
        gameSession
            .actorSoundSources = { [weak adapter] in
                adapter?.graphEvents.actorSoundSources() ?? []
            }
        gameSession.worldTick.register(.actorGraphs) { [weak adapter] delta in
            adapter?.graphs.tick(deltaTime: delta)
        }
    }
}
