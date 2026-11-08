// `ScriptSoundBindingsAdapter` joins the started session: what `wireSounds` registered.

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

/// Connects `ScriptSoundBindingsAdapter` to the started session.
public struct ScriptSoundsWiring {
    public init(_ adapter: ScriptSoundBindingsAdapter, _ hooks: inout PapyrusGameNatives) {
        hooks.playSound = { [weak game = adapter.game] sound, source, token in
            guard
                let game, let director = game.gameSession?.soundDirector,
                let id = game.scripts.bridge?.localFormID(of: sound),
                let position = game.scripts.bridge?.referenceState(for: source)?.transform.position
            else { return 0 }
            return director.playScriptSound(formID: id, at: position, waitToken: token)
        }
        hooks
            .stopSound = { [weak game = adapter.game] id in
                game?.gameSession?.soundDirector?.stopScriptSound(id)
            }
        hooks.setSoundVolume = { [weak game = adapter.game] id, volume in
            game?.gameSession?.soundDirector?.setScriptSoundVolume(id, volume)
        }
        hooks.setParticleGeometry = { [weak game = adapter.game] geometry, seconds in
            guard let session = game?.gameSession else { return }
            guard let geometry else {
                session.scriptParticles.remove(fadeOut: seconds)
                return
            }
            guard
                case let .plugin(plugin, objectID) = geometry,
                let record = session.imageSpaceLinks?.records.shaderParticles
                    .record(ResolvedFormID(plugin: plugin, objectID: objectID))?.record
            else { return }
            session.scriptParticles.apply(record, fadeIn: seconds)
        }
    }
}
