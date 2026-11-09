// The Papyrus natives `ScriptSoundBindingsAdapter` fills as the bridge is built.

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

extension ScriptSoundBindingsAdapter {
    /// Fills these natives as the bridge is built.
    public func fillSounds(_ hooks: inout PapyrusGameNatives) {
        hooks.playSound = { [weak game = self.game] sound, source, token in
            guard
                let game, let director = game.gameSession?.soundDirector,
                let id = game.scripts.bridge?.localFormID(of: sound),
                let position = game.scripts.bridge?.referenceState(for: source)?.transform.position
            else { return 0 }
            return director.playScriptSound(formID: id, at: position, waitToken: token)
        }
        hooks
            .stopSound = { [weak game = self.game] id in
                game?.gameSession?.soundDirector?.stopScriptSound(id)
            }
        hooks.setSoundVolume = { [weak game = self.game] id, volume in
            game?.gameSession?.soundDirector?.setScriptSoundVolume(id, volume)
        }
        hooks.setParticleGeometry = { [weak game = self.game] geometry, seconds in
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
