// App side of `AudioCoordinator`: answers `AudioWorld` from the renderer and
// the streamer. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// Answers `AudioWorld` from the session systems `game` owns.
final class AudioWorldAdapter {
    unowned let game: GameViewController

    init(game: GameViewController) {
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
    }
}

extension AudioWorldAdapter: AudioWorld {
    var audioWorldData: (any WorldDataProviding)? {
        game.worldData
    }

    var audioFileSystem: (any GameFileSource)? {
        game.audioFileSystem
    }

    var audioListenerPose: (position: SIMD3<Float>, yaw: Float) {
        let camera = game.renderer?.freeFlyCamera
        return (camera?.position ?? .zero, camera?.yaw ?? 0)
    }

    var playerFeetArmatures: [FormID]? {
        game.renderer?.playerBody?.feetArmatures
    }

    var playerGait: LocomotionGait? {
        game.renderer?.locomotion.status.gait
    }

    var playerFeetPosition: SIMD3<Float>? {
        game.renderer?.walkController.feetPosition
    }

    var audioAnimationTime: Float {
        game.renderer?.animationTime ?? 0
    }

    func lipSyncTarget() -> LipSyncPlayback? {
        guard
            let renderer = game.renderer,
            let key = game.dialogueMenu.speakerOrTarget,
            let actor = game.streamer?.referenceEntry(key: key)?.placedActor?.formID
        else { return nil }
        return renderer.scene.animations.lazy
            .compactMap { $0 as? LipSyncPlayback }
            .first { $0.actor == actor }
    }

    func installAudio(
        engine: WorldAudioEngine,
        music: WorldMusicDirector,
        footsteps: WorldAudioFootstepDirector
    ) {
        game.renderer?.worldAudio = engine
        game.renderer?.musicDirector = music
        game.renderer?.footstepDirector = footsteps
        let store = (game.worldData as? AudioDataProviding)?.footstepStore
        footsteps.onImpact = { [weak game] impact, position in
            game?.effects.showImpact(
                impact, decal: store?.decal(of: impact), at: position, on: .ground
            )
        }
    }
}
