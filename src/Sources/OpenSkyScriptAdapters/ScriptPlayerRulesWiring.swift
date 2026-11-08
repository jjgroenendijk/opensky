// `ScriptPlayerBindingsAdapter` joins the started session: what `wirePlayerRules` registered.

import Foundation
import MetalKit
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
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

/// Connects `ScriptPlayerBindingsAdapter` to the started session.
public struct ScriptPlayerRulesWiring {
    public init(_ adapter: ScriptPlayerBindingsAdapter, _ hooks: inout PapyrusGameNatives) {
        hooks
            .setGodMode = { [weak game = adapter.game] isOn in
                game?.actorValues.runtime?.setGodMode(isOn)
            }
        hooks.setFootIK = { [weak game = adapter.game] isOn in
            game?.actorGraphs.footIk = isOn
            game?.gameSession?.locomotion.footIk = isOn
        }
        hooks.clearPrison = { [weak game = adapter.game] in game?.crime.clearPrison() }
        hooks.setPlayerReportsCrime = { [weak game = adapter.game] reports in
            game?.crime.reporter?.setReportsPlayerCrimes(reports)
        }
        hooks
            .playerGrabbedReference = { [weak game = adapter.game] in
                game?.magic.playerGrabbedReference
            }
        hooks
            .packageLocation = { [weak game = adapter.game] actor in
                game?.packages.packageLocation(of: actor)
            }
        hooks.forceRagdoll = { [weak game = adapter.game] key in
            game?.ragdoll.runtime?.activate(key, instant: true) ?? false
        }
        hooks.addBallAndSocket = { [weak owner = adapter.owner] first, second in
            owner?.physicsBindings.addBallAndSocket(
                ScriptPlayerBindingsAdapter.linkEnd(first),
                ScriptPlayerBindingsAdapter.linkEnd(second)
            )
                ?? .returned(.boolean(false))
        }
        hooks.removeConstraints = { [weak owner = adapter.owner] first, second in
            owner?.physicsBindings
                .removeConstraints(
                    ScriptPlayerBindingsAdapter.linkEnd(first),
                    ScriptPlayerBindingsAdapter.linkEnd(second)
                ) ?? false
        }
        hooks.setEyeTexture = { [weak game = adapter.game] actor, textureSet in
            guard let game, let set = game.scripts.bridge?.localFormID(of: textureSet) else {
                return false
            }
            if actor == .player || actor == .playerReference {
                game.player.eyeTextureSet = set
                return true
            }
            guard let cell = game.streamer?.cellLocation(of: actor) else { return false }
            game.worldState.setEyeTexture(set, for: actor, in: cell)
            return true
        }
    }
}
