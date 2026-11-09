import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `ActorGraphWorldAdapter`.
extension ActorGraphWorldAdapter {
    public func actorGraphFired(_ fired: String, from actor: ReferenceKey) {
        graphEvents.actorGraphFired(fired, from: actor)
    }
}
