// App side of `LoadingScreenCoordinator`: door transitions start and end it,
// the renderer draws the cover object and the text, and a menu entry pauses
// the world. The rules live in the coordinator. See docs/engine/loading-screens.md.

import Foundation
import OpenSkyCells
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyQuests
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyWorld
import simd

/// What `LoadingScreenWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol LoadingScreenWorldHost: MenuInputConsumer {
    var hud: HUDCoordinator { get }
    var journal: JournalCoordinator { get }
    var loadingScreens: LoadingScreenCoordinator { get }
    var menuMode: MenuModeController { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var runtimeState: RuntimeStateCoordinator { get }
    var runtimeStateWorld: RuntimeStateWorldAdapter { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
}

final class LoadingScreenWorldAdapter {
    static let identifier: MenuIdentifier = "LoadingMenu"

    unowned let game: any LoadingScreenWorldHost
    private var meshes: MeshLibrary?
    private var failedModels: Set<String> = []
    /// When the session-start cover went up; nil once it lifted.
    private var startCoverSince: Double?
    /// A stuck build must not trap the player behind the cover.
    static let startCoverLimitSeconds = 60.0

    init(game: any LoadingScreenWorldHost) {
        self.game = game
    }

    var now: Double {
        Date().timeIntervalSinceReferenceDate
    }

    func wire(streamer: CellStreamer, gameSession: GameSession) {
        streamer.onDoorTransitionStarted = { [weak self] in
            guard let self else { return }
            game.loadingScreens.begin(at: now)
        }
        streamer.onDoorTransitionFinished = { [weak self] scene in
            guard let self else { return }
            guard let scene else {
                game.loadingScreens.cancel()
                return
            }
            game.loadingScreens.destinationReady(location: location(of: scene), at: now)
        }
        gameSession.frameSteps.register(.loadingScreen) { [weak self] _ in
            guard let self else { return }
            liftStartCoverIfReady()
            game.loadingScreens.tick(time: now)
        }
    }

    /// Covers the session start until the near grid and the first distant ring
    /// are in, as the game does, so the world never opens with bare sky.
    func coverSessionStart() {
        guard game.streamer != nil else { return }
        startCoverSince = now
        game.loadingScreens.beginLoad(at: now)
    }

    private func liftStartCoverIfReady() {
        guard let since = startCoverSince, let streamer = game.streamer else { return }
        let timedOut = now - since > Self.startCoverLimitSeconds
        guard streamer.startAreaReady || timedOut else { return }
        startCoverSince = nil
        if timedOut {
            Self.logger.warning("[WARNING] start area not ready in time; cover lifted")
        }
        let seconds = String(format: "%.2f", now - since)
        Self.logger.notice("[INFO] start cover lifted after \(seconds, privacy: .public) s")
        game.loadingScreens.loadFinished(at: now)
    }

    /// The destination cell's location, which is where the player stands when the screen is chosen.
    private func location(of scene: CellScene) -> ResolvedFormID? {
        game.runtimeStateWorld.location(of: scene)
    }

    private func placement(
        _ frame: LoadingCoverFrame,
        gameSession: GameSession
    ) -> [RenderPlacement] {
        let renderer = gameSession.renderer
        guard
            frame.drawsObject, let path = frame.model,
            !failedModels.contains(path) else { return [] }
        if
            meshes == nil,
            let fileSystem = game.worldData?.scriptFileSystem
        {
            meshes = (try? TextureLibrary(fileSystem: fileSystem, device: renderer.device)).map {
                MeshLibrary(fileSystem: fileSystem, device: renderer.device, textures: $0)
            }
        }
        do {
            guard let model = try meshes?.model(path: path) else { return [] }
            let view = gameSession.dialogueCameraState.restorePose ?? gameSession.freeFlyCamera
            let radius = meshes?.bounds(forPath: path)
                .map { simd_length($0.max - $0.min) / 2 } ?? 64
            return [RenderPlacement(
                model: model,
                transform: frame.objectTransform(
                    eye: view.position, yaw: view.yaw, pitch: view.pitch, radius: radius
                ),
                castsShadows: false,
                layer: .loadingCover
            )]
        } catch {
            failedModels.insert(path)
            Self.logger.warning("[WARNING] loading screen model failed: \(path, privacy: .public)")
            return []
        }
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Loading"
    )
}

extension LoadingScreenWorldAdapter: LoadingScreenWorld {
    var presentationRecords: PresentationRecordStore? {
        game.worldData?.presentationRecords
    }

    func loadingConditionContext() -> ConditionContext {
        game.runtimeState.conditionContext()
    }

    func loadingText(of screen: ResolvedRecord<LoadScreen>) -> String? {
        DialogueMenuModel.text(
            screen.record.description,
            kind: .strings,
            strings: game.journal.strings?.scoped(to: screen.sourcePlugin)
        )
    }

    func presentLoadingCover(_ frame: LoadingCoverFrame?) {
        guard let renderer = game.renderer, let gameSession = game.gameSession else { return }
        do {
            if let frame, frame.drawsObject {
                try renderer.setLoadingCover(placement(frame, gameSession: gameSession))
            } else {
                try renderer.setLoadingCover(nil)
            }
        } catch {
            Self.logger
                .error(
                    "[ERROR] loading cover failed: \(String(describing: error), privacy: .public)"
                )
        }
        gameSession.uiScene = frame?.overlay ?? .empty
        game.hud.setCovered(frame != nil)
    }

    func setLoadingPaused(_ paused: Bool) {
        if paused {
            game.menuMode.inputConsumer = game
            game.menuMode.present(Self.identifier)
        } else {
            game.menuMode.dismiss(Self.identifier)
        }
    }
}
