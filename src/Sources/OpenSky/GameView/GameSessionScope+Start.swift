// Starts a session scope over its frame session, and answers what the adapters
// read from the app scope through it.

import AppKit
import MetalKit
import OpenSkyActorPresentation
import OpenSkyAgentAdapters
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagic
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionAdapters
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyStoryAdapters
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension GameSessionScope {
    /// Starts what the built session runs at once, then opens what the launcher asked for.
    func start() {
        guard let stage else { return }
        effects.applyGraphicsSettings(playerSettings.store)
        hud.start()
        controllerRumble.settings = ShoutRumbleSettings.resolve(store: stage.data.gameSettings)
        controllerRumble.isEnabled = { [store = playerSettings.store] in store.bool(.vibration) }
        stage.gameSession.locomotion.waterPushRace = effectsWorld.waterPushRace(of: .player)
        messages.reloadHelpRecords()
        player.requestBody()
        if scripts.bridge != nil {
            scripts.startQuestScripts()
        }
        storyWorld.runSessionStartLists()
        // The engine reads the world's sound records once, so it starts after they load.
        audio.audioEnabled = playerSettings.store.bool(.audioEnabled)
        openLaunchChoice()
    }

    /// After the world data, because the title's logo loads through it.
    private func openLaunchChoice() {
        let launch = services.launch
        if let continueSlot = launch.continueSlot {
            loadingWorld.coverSessionStart()
            titleMenu.load(continueSlot)
        } else if launch.launchStart != .normal {
            menuWorld.teleports.startPlayer(at: launch.launchStart)
        } else if launch.startsAtTitleScreen || playerSettings.store.bool(.startAtTitleScreen) {
            openTitleScreen()
        } else {
            loadingWorld.coverSessionStart()
        }
    }

    /// The game plays its logo movie before the title menu.
    private func openTitleScreen() {
        guard playerSettings.store.bool(.startupLogo) else {
            titleMenu.open()
            return
        }
        movieWorld.playStartupLogo { [weak self] in self?.titleMenu.open() }
    }

    /// The playback drawing one resident actor, matched by its ACHR.
    func actorPlayback(for key: ReferenceKey) -> ActorAnimationPlayback? {
        guard let actor = streamer.referenceEntry(key: key)?.placedActor else { return nil }
        return renderer?.scene.actorPlayback(for: actor.formID)
    }

    /// The pose one actor's clip holds now, keyed by bone name.
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]? {
        guard let renderer, let playback = actorPlayback(for: key) else { return nil }
        return playback.clip.namedWorldTransforms(at: renderer.animationTime)
    }
}

// MARK: - The app scope's services

extension GameSessionScope {
    var renderer: Renderer? {
        gameSession?.renderer
    }

    var hostView: NSView {
        services.hostView
    }

    var cameraInput: CameraInputState {
        services.cameraInput
    }

    var simulationClock: SteppedWallClock {
        services.simulationClock
    }

    var menuMode: MenuModeController {
        services.menuMode
    }

    var swfMovies: SWFMovieSource {
        services.swfMovies
    }

    var localizedStringsLoader: (() -> LocalizedStrings)? {
        services.localizedStringsLoader
    }

    var audioFileSystem: (any GameFileSource)? {
        services.audioFileSystem
    }

    var menuTextLoader: (() -> LocalizedLabels)? {
        services.menuTextLoader
    }

    var controlMapLoader: (() throws -> ControlMapFile)? {
        services.controlMapLoader
    }

    var sessionStartTiming: SessionStartTiming {
        services.sessionStart.timing
    }

    var worldLoadReport: WorldLoadReport? {
        services.worldLoadReport
    }

    var benchmarkLoadPhases: LoadPhaseRecorder? {
        services.benchmarkLoadPhases
    }

    var dataRoot: GameDataRoot? {
        services.dataRoot
    }

    var terrainLODConfigurationStore: TerrainLODConfigurationStore {
        services.terrainLODConfigurationStore
    }

    var soundMixTimings: SoundMixTimings {
        services.soundMixTimings
    }
}

extension GameSessionScope {
    var viewCamera: FreeFlyCamera? {
        gameSession?.freeFlyCamera
    }

    var uiScene: UIScene {
        get { gameSession?.uiScene ?? .empty }
        set { gameSession?.uiScene = newValue }
    }

    var audioEnabled: Bool {
        audio.audioEnabled
    }

    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    func quitToMainMenu() {
        systemMenu.close()
        titleMenu.open()
    }

    func runCommand(_ action: GameInputAction) {
        menuRouter.run(action)
    }

    func handleMenuInput(_ event: MenuInputEvent) {
        menuRouter.route(event)
    }

    func handleMenuPointer(_ event: MenuPointerEvent) {
        menuRouter.route(event)
    }
}

extension GameSessionScope: RenderControlWorld {
    var playerSettingsStore: PlayerSettingsStore {
        services.playerSettingsStore
    }

    func refocusGameView() {
        unsafe hostView.window?.makeFirstResponder(hostView)
    }
}
