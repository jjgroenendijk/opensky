import Foundation
import OpenSkyActors
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
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
