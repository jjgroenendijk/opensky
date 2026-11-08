// `ObjectAnimationWorldAdapter` joins the started session: what `wire` registered.

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyObjectAnimation
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// After the vehicles, so a cart's events and an object's events keep one order.
public struct ObjectAnimationWiring {
    public init(_ adapter: ObjectAnimationWorldAdapter, gameSession: GameSession) {
        guard adapter.game.audioFileSystem != nil else { return }
        gameSession.worldTick.register(.objectAnimation) { [weak adapter] delta in
            adapter?.advance(delta)
        }
    }
}
