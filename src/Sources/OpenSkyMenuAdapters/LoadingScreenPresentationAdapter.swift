import Foundation
import OpenSkyCells
public import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyGameData
public import OpenSkyLoading
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
public import OpenSkySessionInterface
import OpenSkyTerrain
import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// What `LoadingScreenPresentationAdapter` reads from the session.
@MainActor
public protocol LoadingScreenPresentationHost: MenuInputConsumer, SendableMetatype {
    var gameSession: (any GameSessionPort)? { get }
    var hud: any HUDPort { get }
    var journal: any JournalPort { get }
    var menuMode: any MenuModePort { get }
    var progression: any ProgressionPort { get }
    var renderer: (any RendererPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var menuRecords: (any MenuRecordsPort)? { get }
}

/// Part of `LoadingScreenWorldAdapter`, over its own narrow host.
public struct LoadingScreenPresentationAdapter {
    public let game: any LoadingScreenPresentationHost
    public let state: LoadingScreenPartState
    public let movie: MenuMovieOverlay
}

extension LoadingScreenPresentationAdapter {
    /// Starts the game's loading movie for a screen with a tip, fades it with the
    /// cover, and stops it when the cover lifts.
    private func presentMovie(_ frame: LoadingCoverFrame?) {
        guard let frame, let text = frame.text, !text.isEmpty else {
            if frame == nil {
                stopMovie()
            }
            return
        }
        if state.movieText != text {
            startMovie(text: text)
        }
        if !frame.drawsObject, !state.movieFadedOut, movie.isLoaded {
            state.movieFadedOut = true
            attempt { try game.renderer?.updateSWFOverlay(LoadingMenuMovieBridge.fadeOut(runtime:))
            }
        }
    }

    func startMovie(text: String) {
        state.movieText = text
        state.shownTip = text
        state.tipRequests = 0
        state.movieFadedOut = false
        let content = movieContent(text: text)
        movie.start(
            path: LoadingMenuMovieBridge.moviePath,
            prepare: { [weak state] runtime in
                LoadingMenuMovieBridge.prepare(runtime: runtime) { state?.requestTip() ?? "" }
            },
            activate: { LoadingMenuMovieBridge.activate(runtime: $0, content: content) }
        )
    }

    var isMovieLoaded: Bool {
        movie.isLoaded
    }

    private func stopMovie() {
        guard state.movieText != nil else { return }
        state.movieText = nil
        movie.stop()
    }

    private func movieContent(text: String) -> LoadingMenuContent {
        let player = game.progression.skillsMenuPlayer
        return LoadingMenuContent(
            text: text, level: player.level, levelProgress: player.levelProgress
        )
    }

    var presentationRecords: PresentationRecordStore? {
        game.menuRecords?.presentationRecords
    }

    public func loadingConditionContext() -> ConditionContext {
        game.runtimeState.conditionContext()
    }

    public func loadingText(of screen: ResolvedRecord<LoadScreen>) -> String? {
        DialogueMenuModel.text(
            screen.record.description,
            kind: .strings,
            strings: game.journal.strings?.scoped(to: screen.sourcePlugin)
        )
    }

    public func presentLoadingCover(_ frame: LoadingCoverFrame?) {
        guard let renderer = game.renderer, let gameSession = game.gameSession else { return }
        do {
            if let frame, frame.drawsObject, frame.model != nil {
                try renderer.setLoadingScene(coverScene(frame, gameSession: gameSession))
            } else {
                state.mist = nil
                try renderer.setLoadingCover(frame?.drawsObject == true ? [] : nil)
            }
        } catch {
            LoadingScreenLog.logger
                .error(
                    "[ERROR] loading cover failed: \(String(describing: error), privacy: .public)"
                )
        }
        presentMovie(frame)
        gameSession.uiScene = frame?.overlay(showsText: !movie.isLoaded) ?? .empty
        game.hud.setCovered(frame != nil)
    }

    public func setLoadingPaused(_ paused: Bool) {
        if paused {
            game.menuMode.inputConsumer = game
            game.menuMode.present(MenuIdentifier.loadingMenu)
        } else {
            game.menuMode.dismiss(MenuIdentifier.loadingMenu)
        }
    }
}

extension LoadingScreenPresentationAdapter {
    /// The game's scene for `frame`: its camera, its lights, the mist, and the model.
    public func coverScene(
        _ frame: LoadingCoverFrame,
        gameSession: any GameSessionPort
    ) -> LoadingCoverScene {
        let renderer = gameSession.renderer
        var scene = LoadingCoverScene(
            placements: [], pointLights: LoadingScreenScene.lights,
            lighting: LoadingScreenScene.lighting,
            camera: LoadingCoverCamera(
                view: LoadingScreenScene.camera(pathNode: cameraPathNode(frame)),
                horizontalFieldOfView: LoadingScreenScene.horizontalFieldOfView(frame.fieldOfView)
            )
        )
        guard let meshes = meshLibrary(renderer: renderer) else { return scene }
        let mist = mist(meshes: meshes)
        scene.placements = mist?.placements ?? []
        scene.particles = mist?.particles ?? []
        scene.placements += placement(
            frame,
            meshes: meshes,
            aspectRatio: renderer.drawableAspectRatio
        )
        return scene
    }

    private func meshLibrary(renderer: any RendererPort) -> MeshLibrary? {
        if
            state.meshes == nil,
            let fileSystem = game.menuRecords?.scriptFileSystem
        {
            let textures = attempt {
                try TextureLibrary(fileSystem: fileSystem, device: renderer.device)
            }
            state.meshes = textures.map {
                MeshLibrary(fileSystem: fileSystem, device: renderer.device, textures: $0)
            }
        }
        return state.meshes
    }

    private func placement(
        _ frame: LoadingCoverFrame, meshes: MeshLibrary, aspectRatio: Float
    ) -> [RenderPlacement] {
        guard let path = frame.model, !state.failedModels.contains(path) else { return [] }
        do {
            let model = try meshes.model(path: path)
            let marker = InventoryItemPreview.meshPath(path)
                .flatMap { state.modelMarkers?.value(for: $0) }
            let pose = frame.modelPose(markerRotation: marker?.rotation)
            return [RenderPlacement(
                model: model,
                transform: LoadingScreenScene.modelTransform(pose, aspectRatio: aspectRatio),
                castsShadows: true,
                layer: .loadingCover
            )]
        } catch {
            state.failedModels.insert(path)
            LoadingScreenLog.logger
                .warning("[WARNING] loading screen model failed: \(path, privacy: .public)")
            return []
        }
    }

    /// The mist, built once per cover so its particles run on. The model still
    /// shows when the mist fails to load.
    private func mist(meshes: MeshLibrary) -> LoadingMist? {
        if let mist = state.mist {
            return mist
        }
        let path = LoadingScreenScene.mistPath
        guard !state.failedModels.contains(path) else { return nil }
        do {
            let transform = LoadingScreenScene.mistTransform
            let mist = try LoadingMist(
                placements: [RenderPlacement(
                    model: meshes.model(path: path), transform: transform,
                    castsShadows: false, layer: .loadingCover
                )],
                particles: meshes.particlePlaybacks(
                    path: path, placementTransform: transform, formID: 0
                )
            )
            state.mist = mist
            return mist
        } catch {
            state.failedModels.insert(path)
            LoadingScreenLog.logger
                .warning("[WARNING] loading screen mist failed: \(path, privacy: .public)")
            return nil
        }
    }

    private func cameraPathNode(_ frame: LoadingCoverFrame) -> SIMD3<Float> {
        guard let path = frame.cameraPath, let track = state.cameraPaths?.value(for: path) else {
            return .zero
        }
        return track.nodePosition(after: frame.elapsedSeconds)
    }
}

extension LoadingScreenPartState {
    /// The game shows the chosen screen's tip first; each later request from the
    /// movie draws another random screen's tip.
    func requestTip() -> String {
        tipRequests += 1
        if tipRequests > 1, let next = nextTip?() {
            shownTip = next
        }
        return shownTip ?? movieText ?? ""
    }
}
