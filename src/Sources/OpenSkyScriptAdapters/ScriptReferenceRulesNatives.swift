// The Papyrus natives `ScriptReferenceBindingsAdapter` fills as the bridge is built.

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

extension ScriptReferenceBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillReferenceRules(_ hooks: inout PapyrusGameNatives) {
        hooks.clearExtraArrows = { [weak game = self.game] actor in
            guard let game, let host = game.streamer.referenceEntry(key: actor)?.formID else {
                return 0
            }
            return game.combat.removeArrows(stuckIn: host)
        }
        hooks.playImpact = { dataSet, pick in
            guard
                let id = self.game.scripts.bridge?.localFormID(of: dataSet),
                let hit = self.impactHit(of: pick),
                let impact = self.game.combatWorld.impact(dataSet: id, material: hit.material)
            else { return false }
            self.game.combatWorld.playImpact(impact, at: hit.position)
            return true
        }
        hooks.resetCell = { [weak game = self.game] cell in
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
