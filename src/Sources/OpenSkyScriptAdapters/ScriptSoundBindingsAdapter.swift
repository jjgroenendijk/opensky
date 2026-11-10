import Foundation
import MetalKit
import OpenSkyActorPresentation
import OpenSkyAgentControl
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyEffects
public import OpenSkyFormatsESM
import OpenSkyGameData
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
    public let game: any ScriptSoundBindingsHost
    let state: ScriptPartState

    init(game: any ScriptSoundBindingsHost, state: ScriptPartState) {
        self.game = game
        self.state = state
    }
}

extension ScriptSoundBindingsAdapter {
    /// Answers each `Sound.PlayAndWait` whose sound ended. An answer the scheduler
    /// cannot take yet waits for the next frame.
    func answerSoundWaits() {
        if let director = game.gameSession?.soundDirector {
            state.soundWaitAnswers.merge(director.retireScriptSounds()) { first, _ in first }
        }
        guard let scheduler = game.scripts.runtime?.scheduler else { return }
        state.soundWaitAnswers = state.soundWaitAnswers.filter { token, played in
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
