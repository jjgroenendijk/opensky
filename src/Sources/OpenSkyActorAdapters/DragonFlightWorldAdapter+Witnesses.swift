import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `DragonFlightWorldAdapter`.
extension DragonFlightWorldAdapter {
    public func actorFliesPackages(_ actor: ReferenceKey) -> Bool {
        candidates.actorFliesPackages(actor)
    }
}
