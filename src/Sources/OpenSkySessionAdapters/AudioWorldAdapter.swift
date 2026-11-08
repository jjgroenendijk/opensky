// App side of `AudioCoordinator`: answers `AudioWorld` from the renderer and
// the streamer. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorPresentation
public import OpenSkyAudio
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AudioWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol AudioWorldHost: AnyObject {
    var audio: any AudioPort { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var combat: any CombatPort { get }
    var soundMixTimings: SoundMixTimings { get }
    var controllerRumble: any ControllerRumblePort { get }
    var effects: any EffectsPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var worldData: WorldDataStores? { get }
    /// Hands the started engine and directors to the session, which owns them.
    func takeStartedAudio(
        engine: WorldAudioEngine, sounds: WorldAudioSoundDirector,
        music: WorldMusicDirector, footsteps: WorldAudioFootstepDirector
    )
}

/// Answers `AudioWorld` from the session systems `game` owns.
public final class AudioWorldAdapter {
    public unowned let game: any AudioWorldHost

    public let listenerHost: any AudioListenerHost
    public let mixHost: any AudioMixHost

    public var listener: AudioListenerAdapter {
        AudioListenerAdapter(owner: self, game: listenerHost)
    }

    public var mix: AudioMixAdapter {
        AudioMixAdapter(owner: self, game: mixHost)
    }

    public init(game: some AudioWorldHost & AudioListenerHost & AudioMixHost) {
        listenerHost = game
        mixHost = game
        self.game = game
    }
}

extension AudioWorldAdapter: AudioWorld {
    public var audioWorldData: WorldDataStores? {
        game.worldData
    }

    public var audioFileSystem: (any GameFileSource)? {
        game.audioFileSystem
    }

    public func audioStarted(
        engine: WorldAudioEngine,
        sounds: WorldAudioSoundDirector,
        music: WorldMusicDirector,
        footsteps: WorldAudioFootstepDirector
    ) {
        game.takeStartedAudio(engine: engine, sounds: sounds, music: music, footsteps: footsteps)
        if let store = game.worldData?.soundStore {
            engine.soundMix = SoundCategoryMix(
                categories: store.categories, roles: store.categoryRoles,
                timings: game.soundMixTimings
            )
        }
        game.gameSession?.soundRumble = { [weak self] levels in
            guard let self else { return }
            let melee = game.combat.melee
            let power = melee.map {
                $0.state.attackPhase.isAttacking && $0.strikeKind.isPowerAttack
            } ?? false
            game.controllerRumble.follow(levels.motors(powerAttack: power))
        }
        game.gameSession?
            .soundMixInputs = { [weak self] in self?.mix.soundMixInputs() ?? SoundMixInputs() }
        let store = game.worldData?.footstepStore
        footsteps.onImpact = { [weak game] impact, position in
            game?.effects.showImpact(
                impact, decal: store?.decal(of: impact), at: position, on: .ground
            )
        }
    }
}

extension AudioWorldAdapter: AudioWorldPort {}
