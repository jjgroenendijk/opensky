// App side of `AudioCoordinator`: answers `AudioWorld` from the renderer and
// the streamer. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyCells
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldState
import simd

/// What `AudioWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol AudioWorldHost: AnyObject {
    var audio: AudioCoordinator { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var dialogueMenu: DialogueMenuController { get }
    var dialogueWorld: DialogueWorldAdapter { get }
    var effects: EffectsCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var runtimeState: RuntimeStateCoordinator { get }
    var runtimeStateWorld: RuntimeStateWorldAdapter { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
}

/// Answers `AudioWorld` from the session systems `game` owns.
final class AudioWorldAdapter {
    unowned let game: any AudioWorldHost

    init(game: any AudioWorldHost) {
        self.game = game
    }

    /// Each callback does nothing until audio is enabled. Papyrus `OnActivate`
    /// subscribes beside the interaction handler through the same `CallbackFanOut`.
    func wireAudioCallbacks(_ streamer: CellStreamer) {
        let audio = game.audio
        streamer.onInteraction.add { [weak audio] event in
            audio?.soundDirector?.handleInteraction(event)
        }
        streamer.onInteractionAnimation = { [weak audio] event in
            audio?.soundDirector?.handleInteractionAnimation(event)
        }
        streamer.onAmbienceContextChanged = { [weak audio] context in
            audio?.soundDirector?.handleAmbienceContext(context)
        }
        streamer.onMusicContextChanged = { [weak audio] context in
            audio?.musicDirector?.handleMusicContext(context)
        }
        streamer.musicFeed.locationMusicType = { [unowned game] scene in
            game.runtimeStateWorld.locationMusicType(of: scene)
        }
    }
}

extension AudioWorldAdapter: AudioWorld {
    var audioWorldData: WorldDataStores? {
        game.worldData
    }

    var audioFileSystem: (any GameFileSource)? {
        game.audioFileSystem
    }

    var audioListenerPose: (position: SIMD3<Float>, yaw: Float) {
        let camera = game.gameSession?.freeFlyCamera
        return (camera?.position ?? .zero, camera?.yaw ?? 0)
    }

    var playerFeetArmatures: [FormID]? {
        game.gameSession?.playerBody?.feetArmatures
    }

    var playerGait: LocomotionGait? {
        game.gameSession?.locomotion.status.gait
    }

    var playerFeetPosition: SIMD3<Float>? {
        game.gameSession?.walkController.feetPosition
    }

    var audioAnimationTime: Float {
        game.renderer?.animationTime ?? 0
    }

    func lipSyncTarget() -> LipSyncPlayback? {
        game.dialogueMenu.speakerOrTarget.flatMap(lipSyncTarget(for:))
    }

    func lipSyncTarget(for speaker: ReferenceKey) -> LipSyncPlayback? {
        guard
            let renderer = game.renderer,
            let actor = game.streamer?.referenceEntry(key: speaker)?.placedActor?.formID
        else { return nil }
        return renderer.scene.animations.lazy
            .compactMap { $0 as? LipSyncPlayback }
            .first { $0.actor == actor }
    }

    func speakerHeadPosition(of speaker: ReferenceKey) -> SIMD3<Float>? {
        game.dialogueWorld.headPosition(of: speaker)
    }

    func playerConditionsPass(_ conditions: [Condition]) -> Bool {
        var context = game.runtimeState.conditionContext()
        context.subject = .player
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(conditions).isTrue
    }

    func installAudio(
        engine: WorldAudioEngine,
        sounds: WorldAudioSoundDirector,
        music: WorldMusicDirector,
        footsteps: WorldAudioFootstepDirector
    ) {
        game.gameSession?.worldAudio = engine
        game.gameSession?.soundDirector = sounds
        game.gameSession?.musicDirector = music
        game.gameSession?.footstepDirector = footsteps
        let store = game.worldData?.footstepStore
        footsteps.onImpact = { [weak game] impact, position in
            game?.effects.showImpact(
                impact, decal: store?.decal(of: impact), at: position, on: .ground
            )
        }
    }
}
