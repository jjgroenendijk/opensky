// `ScriptReferenceBindingsAdapter` joins the started session: what `wireReferenceRules` registered.

import Foundation
import MetalKit
import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyScripting
public import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Connects `ScriptReferenceBindingsAdapter` to the started session.
public struct ScriptReferenceRulesWiring {
    public init(
        _ adapter: ScriptReferenceBindingsAdapter,
        _ hooks: inout PapyrusGameNatives
    ) {
        hooks.clearExtraArrows = { [weak game = adapter.game] actor in
            guard let game, let host = game.streamer.referenceEntry(key: actor)?.formID else {
                return 0
            }
            return game.combat.archery?.projectiles.removeArrows(stuckIn: host) ?? 0
        }
        hooks.playImpact = { dataSet, pick in
            guard
                let id = adapter.game.scripts.bridge?.localFormID(of: dataSet),
                let hit = adapter.impactHit(of: pick),
                let impact = adapter.game.combatWorld.impact(dataSet: id, material: hit.material)
            else { return false }
            adapter.game.combatWorld.playImpact(impact, at: hit.position)
            return true
        }
        hooks.resetCell = { [weak game = adapter.game] cell in
            guard
                let game, let reset = game.gameSession?.cellReset,
                let id = game.scripts.bridge?.localFormID(of: cell),
                let location = game.streamer.placedRecords?.location(ofCell: id)
            else { return false }
            reset.flagForReset(location)
            return true
        }
    }
}
