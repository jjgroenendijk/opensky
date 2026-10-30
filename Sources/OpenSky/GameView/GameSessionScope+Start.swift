// Starts a session scope over its frame session, and answers what the adapters
// read from the app scope through it.

import AppKit
import MetalKit
import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyCombat
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension GameSessionScope {
    /// Wires every system to the frame session and opens what the launcher asked for.
    func start() {
        guard let gameSession, let worldData, let cellRunner else { return }
        effects.applyGraphicsSettings(playerSettings.store)
        hud.start()
        menuRouter.wire(gameSession: gameSession)
        benchmarkWorld.wire(gameSession: gameSession)
        wireMenuMode(gameSession: gameSession)
        sessionWiring.wireStreaming(
            session: CellSession(runner: cellRunner, data: worldData), gameSession: gameSession
        )
        gameSession.worldTick.register(.survivalMode) { [weak self] _ in
            self?.survivalMode.tick()
        }
        // After streaming, so the HUD reads the streamer's update of this frame.
        gameSession.frameSteps.register(.hud) { [weak self] _ in
            guard let self else { return }
            // Before the HUD draws, so a skill notice from this frame shows now.
            progressionWorld.run(progression.takeCommands())
            hud.updatePlayerModes(hudModeInputs(gameSession))
            hud.updateFrame()
        }
        // The engine reads the world's sound records once, so it starts after they load.
        audio.audioEnabled = playerSettings.store.bool(.audioEnabled)
        openLaunchChoice()
    }

    /// The player states the HUD movie has a mode for.
    private func hudModeInputs(_ gameSession: GameSession) -> HUDModeInputs {
        HUDModeInputs(
            movementDisabled: scripts.bridge?.isPlayerMovementEnabled == false,
            sneaking: player.isSneaking,
            swimming: gameSession.walkController.isSwimming,
            ridingHorse: mounts.drive?.kind == .horse,
            weaponDrawn: combat.isWeaponDrawn
        )
    }

    /// After the world data, because the title's logo loads through it.
    private func openLaunchChoice() {
        let launch = services.launch
        if let continueSlot = launch.continueSlot {
            loadingWorld.coverSessionStart()
            titleMenu.load(continueSlot)
        } else if launch.launchStart != .normal {
            menuWorld.startPlayer(at: launch.launchStart)
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

    /// Menu mode drives the renderer's world-sim pause and clears held world
    /// input on entry, so no key sticks while the menu owns input.
    private func wireMenuMode(gameSession: GameSession) {
        let input = cameraInput
        menuMode.onModeChange = { [weak self, weak gameSession, weak input] route, paused in
            gameSession?.worldSimPaused = paused
            self?.menuRouter.modeChanged(to: route)
            // Released on the route flip, not the pause: the dialogue menu
            // captures input without stopping the world.
            if route == .menu {
                input?.releaseAll()
            }
        }
    }

    /// The playback drawing one resident actor, matched by its ACHR.
    func actorPlayback(for key: ReferenceKey) -> ActorAnimationPlayback? {
        guard let actor = streamer?.referenceEntry(key: key)?.placedActor else { return nil }
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
}

extension GameSessionScope: @MainActor SystemMenuWorld {
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
        playerSettings.store
    }

    func refocusGameView() {
        hostView.window?.makeFirstResponder(hostView)
    }
}
