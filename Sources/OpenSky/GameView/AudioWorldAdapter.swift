// App side of `AudioCoordinator`: answers `AudioWorld` from the renderer and
// the streamer. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AudioWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol AudioWorldHost: AnyObject {
    var audio: any AudioPort { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var combat: any CombatPort { get }
    var dialogueMenu: any DialogueMenuPort { get }
    var dialogueWorld: any DialogueWorldPort { get }
    var loadingScreens: any LoadingScreenPort { get }
    var menuMode: any MenuModePort { get }
    var soundMixTimings: SoundMixTimings { get }
    var controllerRumble: any ControllerRumblePort { get }
    var effects: any EffectsPort { get }
    var renderer: (any RendererPort)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
    /// Hands the started engine and directors to the session, which owns them.
    func installAudio(
        engine: WorldAudioEngine, sounds: WorldAudioSoundDirector,
        music: WorldMusicDirector, footsteps: WorldAudioFootstepDirector
    )
}

/// Answers `AudioWorld` from the session systems `game` owns.
final class AudioWorldAdapter {
    unowned let game: any AudioWorldHost

    init(game: any AudioWorldHost) {
        self.game = game
    }

    /// Each callback does nothing until audio is enabled. The activation sound
    /// plays in the first interaction step, before Papyrus `OnActivate`.
    func wireAudioCallbacks(_ streamer: CellStreamer) {
        let audio = game.audio
        streamer.onInteraction.register(.audio) { [weak audio] event in
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
            game.runtimeStateWorld.locationMusicType(of: scene.locationKey)
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

    /// Menu mode means a menu that pauses the world: the dialogue menu leaves voices playing.
    func soundMixInputs() -> SoundMixInputs {
        let menus = game.menuMode
        return SoundMixInputs(
            menuMode: menus.isWorldSimPaused,
            loading: game.loadingScreens.isCovering,
            dialogue: game.dialogueMenu.isOpen,
            statsMenu: menus.stack.identifiers.contains(SkillsMenuCoordinator.identifier)
        )
    }

    func isConversationSpeaker(_ speaker: ReferenceKey) -> Bool {
        game.dialogueMenu.isOpen && game.dialogueMenu.speakerOrTarget == speaker
    }

    func playerConditionsPass(_ conditions: [Condition]) -> Bool {
        var context = game.runtimeState.conditionContext()
        context.subject = .player
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(conditions).isTrue
    }

    func audioStarted(
        engine: WorldAudioEngine,
        sounds: WorldAudioSoundDirector,
        music: WorldMusicDirector,
        footsteps: WorldAudioFootstepDirector
    ) {
        game.installAudio(engine: engine, sounds: sounds, music: music, footsteps: footsteps)
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
            .soundMixInputs = { [weak self] in self?.soundMixInputs() ?? SoundMixInputs() }
        let store = game.worldData?.footstepStore
        footsteps.onImpact = { [weak game] impact, position in
            game?.effects.showImpact(
                impact, decal: store?.decal(of: impact), at: position, on: .ground
            )
        }
    }
}
