// The Papyrus natives `ScriptPlayerBindingsAdapter` fills as the bridge is built.

import Foundation
import MetalKit
import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
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

extension ScriptPlayerBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillPlayerRules(_ hooks: inout PapyrusGameNatives) {
        hooks
            .setGodMode = { [weak game = self.game] isOn in
                game?.actorValues.runtime?.setGodMode(isOn)
            }
        hooks.setFootIK = { [weak game = self.game] isOn in
            game?.actorGraphs.footIk = isOn
            game?.gameSession?.locomotion.footIk = isOn
        }
        hooks.clearPrison = { [weak game = self.game] in game?.crime.clearPrison() }
        hooks.setPlayerReportsCrime = { [weak game = self.game] reports in
            game?.crime.reporter?.setReportsPlayerCrimes(reports)
        }
        hooks
            .playerGrabbedReference = { [weak game = self.game] in
                game?.magic.playerGrabbedReference
            }
        hooks
            .packageLocation = { [weak game = self.game] actor in
                game?.packages.packageLocation(of: actor)
            }
        hooks.forceRagdoll = { [weak game = self.game] key in
            game?.ragdoll.runtime?.activate(key, instant: true) ?? false
        }
        hooks.addBallAndSocket = { [physics = self.physicsBindings] first, second in
            physics.addBallAndSocket(
                ScriptPlayerBindingsAdapter.linkEnd(first),
                ScriptPlayerBindingsAdapter.linkEnd(second)
            )
        }
        hooks.removeConstraints = { [physics = self.physicsBindings] first, second in
            physics.removeConstraints(
                ScriptPlayerBindingsAdapter.linkEnd(first),
                ScriptPlayerBindingsAdapter.linkEnd(second)
            )
        }
        hooks.setEyeTexture = { [weak game = self.game] actor, textureSet in
            guard let game, let set = game.scripts.bridge?.localFormID(of: textureSet) else {
                return false
            }
            if actor == .player || actor == .playerReference {
                game.player.eyeTextureSet = set
                return true
            }
            guard let cell = game.streamer.cellLocation(of: actor) else { return false }
            game.worldState.setEyeTexture(set, for: actor, in: cell)
            return true
        }
    }
}
