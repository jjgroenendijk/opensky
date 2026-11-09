// `EffectGraphWorldAdapter` joins the started session: what `wire` registered.

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface

/// After the actor and object graphs, so the events they raised this frame reach
/// the effect graphs in the same frame.
public struct EffectGraphWiring {
    public init(_ adapter: EffectGraphWorldAdapter, gameSession: GameSession) {
        guard adapter.game.audioFileSystem != nil else { return }
        gameSession.worldTick.register(.effectGraphs) { [weak adapter] delta in
            adapter?.game.effectGraphs.tick(deltaTime: delta)
        }
    }
}
