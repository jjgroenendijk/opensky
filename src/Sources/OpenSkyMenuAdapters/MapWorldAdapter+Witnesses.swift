import Foundation
import OpenSkyActorsInterface
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `MapWorldAdapter`.
extension MapWorldAdapter {
    public var fastTravelContext: FastTravelContext {
        travel.fastTravelContext
    }

    public func travel(to marker: MapMarkerSite) -> Bool {
        travel.travel(to: marker)
    }

    public var questTargets: [QuestTargetMarker] {
        quests.questTargets
    }
}
