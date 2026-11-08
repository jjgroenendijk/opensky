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
public import OpenSkyFormatsESM
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
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `ScriptSoundBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptSoundBindingsHost: AnyObject {
    var audio: any AudioPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var scripts: any ScriptPort { get }
}

/// Part of `ScriptWorldAdapter`, over its own narrow host.
public final class ScriptSoundBindingsAdapter {
    public unowned let owner: ScriptWorldAdapter
    public unowned let game: any ScriptSoundBindingsHost

    public init(owner: ScriptWorldAdapter, game: any ScriptSoundBindingsHost) {
        self.owner = owner
        self.game = game
    }
}

extension ScriptSoundBindingsAdapter {
    public func wireSounds(_ hooks: inout PapyrusGameNatives) {
        hooks.playSound = { [weak game] sound, source, token in
            guard
                let game, let director = game.gameSession?.soundDirector,
                let id = game.scripts.bridge?.localFormID(of: sound),
                let position = game.scripts.bridge?.referenceState(for: source)?.transform.position
            else { return 0 }
            return director.playScriptSound(formID: id, at: position, waitToken: token)
        }
        hooks
            .stopSound = { [weak game] id in game?.gameSession?.soundDirector?.stopScriptSound(id) }
        hooks.setSoundVolume = { [weak game] id, volume in
            game?.gameSession?.soundDirector?.setScriptSoundVolume(id, volume)
        }
        hooks.setParticleGeometry = { [weak game] geometry, seconds in
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

    /// Answers each `Sound.PlayAndWait` whose sound ended. An answer the scheduler
    /// cannot take yet waits for the next frame.
    public func answerSoundWaits() {
        if let director = game.gameSession?.soundDirector {
            owner.soundWaitAnswers.merge(director.retireScriptSounds()) { first, _ in first }
        }
        guard let scheduler = game.scripts.runtime?.scheduler else { return }
        owner.soundWaitAnswers = owner.soundWaitAnswers.filter { token, played in
            !scheduler.answer(token, returning: .boolean(played))
        }
    }
}

extension ScriptSoundBindingsAdapter: PapyrusMusicControlling {
    public func addMusic(_ music: ReferenceKey) -> Bool {
        guard let director = game.audio.musicDirector, let id = musicFormID(music) else {
            return false
        }
        return director.addScriptedMusic(id) == nil
    }

    public func removeMusic(_ music: ReferenceKey) {
        guard let id = musicFormID(music) else { return }
        game.audio.musicDirector?.removeScriptedMusic(id)
    }

    private func musicFormID(_ key: ReferenceKey) -> FormID? {
        guard case let .plugin(plugin, objectID) = key else { return nil }
        return game.scripts.bridge?.formIDResolver?
            .localFormID(of: ResolvedFormID(plugin: plugin, objectID: objectID))
    }
}
