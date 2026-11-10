// App side of `AudioCoordinator`: answers `AudioWorld` from the renderer and
// the streamer. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorPresentation
public import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyLoading
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
    var sessionRecords: (any SessionRecordsPort)? { get }
    /// Hands the started engine and directors to the session, which owns them.
    func takeStartedAudio(_ audio: StartedAudio)
}

/// The engine and directors the audio coordinator started, in one value, so a host
/// that takes them needs no import of the world module.
public struct StartedAudio {
    public let engine: WorldAudioEngine
    public let sounds: WorldAudioSoundDirector
    public let music: WorldMusicDirector
    public let footsteps: WorldAudioFootstepDirector
}

/// Answers `AudioWorld` from the session systems `game` owns.
public final class AudioWorldAdapter {
    public let game: any AudioWorldHost

    public let listenerHost: any AudioListenerHost
    public let mixHost: any AudioMixHost

    public var listener: AudioListenerAdapter {
        AudioListenerAdapter(game: listenerHost)
    }

    public var mix: AudioMixAdapter {
        AudioMixAdapter(game: mixHost)
    }

    public init(game: some AudioWorldHost & AudioListenerHost & AudioMixHost) {
        listenerHost = game
        mixHost = game
        self.game = game
    }
}

extension AudioWorldAdapter {
    /// Gives the engine the loaded sound categories; without them it keeps its own mix.
    /// The footstep records, which name the decal each impact leaves.
    public var footstepStore: FootstepStore? {
        game.sessionRecords?.footstepStore
    }

    public func applySoundMix(to engine: WorldAudioEngine) {
        guard let store = game.sessionRecords?.soundStore else { return }
        engine.soundMix = SoundCategoryMix(
            categories: store.categories, roles: store.categoryRoles,
            timings: game.soundMixTimings
        )
    }
}

extension AudioWorldAdapter: AudioWorld {
    public var audioWorldData: (any AudioRecordsPort)? {
        game.sessionRecords
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
        let audio = StartedAudio(engine: engine, sounds: sounds, music: music, footsteps: footsteps)
        game.takeStartedAudio(audio)
        applySoundMix(to: engine)
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
        let store = footstepStore
        footsteps.onImpact = { [weak game] impact, position in
            game?.effects.showImpact(
                impact, decal: store?.decal(of: impact), at: position, on: .ground
            )
        }
    }
}
