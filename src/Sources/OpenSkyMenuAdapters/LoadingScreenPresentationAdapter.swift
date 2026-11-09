import Foundation
public import OpenSkyCells
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
public import OpenSkyRenderCore
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
public protocol LoadingScreenPresentationHost: MenuInputConsumer {
    var gameSession: (any GameSessionPort)? { get }
    var hud: any HUDPort { get }
    var journal: any JournalPort { get }
    var menuMode: any MenuModePort { get }
    var progression: any ProgressionPort { get }
    var renderer: (any RendererPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var worldData: WorldDataStores? { get }
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

    public func startMovie(text: String) {
        state.movieText = text
        state.movieFadedOut = false
        let content = movieContent(text: text)
        movie.start(
            path: LoadingMenuMovieBridge.moviePath,
            prepare: { [weak state] runtime in
                LoadingMenuMovieBridge.prepare(runtime: runtime) { state?.movieText ?? "" }
            },
            activate: { LoadingMenuMovieBridge.activate(runtime: $0, content: content) }
        )
    }

    public var isMovieLoaded: Bool {
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

    public var presentationRecords: PresentationRecordStore? {
        game.worldData?.presentationRecords
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
            if let frame, frame.drawsObject {
                let view = coverView(gameSession)
                try renderer.setLoadingCover(
                    placement(frame, gameSession: gameSession),
                    lighting: LoadingCoverFrame.lighting(yaw: view.yaw, pitch: view.pitch)
                )
            } else {
                try renderer.setLoadingCover(nil)
            }
        } catch {
            LoadingScreenWorldAdapter.logger
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
            game.menuMode.present(LoadingScreenWorldAdapter.identifier)
        } else {
            game.menuMode.dismiss(LoadingScreenWorldAdapter.identifier)
        }
    }
}

extension LoadingScreenPresentationAdapter {
    /// A model's radius is half its bound's diagonal.
    private static let halfDiagonal: Float = 0.5
    /// The radius of a cover model whose bound is unknown, in units.
    private static let fallbackCoverRadius: Float = 64

    public func placement(
        _ frame: LoadingCoverFrame,
        gameSession: any GameSessionPort
    ) -> [RenderPlacement] {
        let renderer = gameSession.renderer
        guard
            frame.drawsObject, let path = frame.model,
            !state.failedModels.contains(path) else { return [] }
        if
            state.meshes == nil,
            let fileSystem = game.worldData?.scriptFileSystem
        {
            let textures = attempt {
                try TextureLibrary(fileSystem: fileSystem, device: renderer.device)
            }
            state.meshes = textures.map {
                MeshLibrary(fileSystem: fileSystem, device: renderer.device, textures: $0)
            }
        }
        do {
            guard let model = try state.meshes?.model(path: path) else { return [] }
            let view = coverView(gameSession)
            let radius = state.meshes?.bounds(forPath: path)
                .map { simd_distance($0.max, $0.min) * Self.halfDiagonal } ?? Self
                .fallbackCoverRadius
            return [RenderPlacement(
                model: model,
                transform: frame.objectTransform(
                    eye: view.position, yaw: view.yaw, pitch: view.pitch, radius: radius,
                    cameraOffset: cameraOffset(frame)
                ),
                castsShadows: false,
                layer: .loadingCover
            )]
        } catch {
            state.failedModels.insert(path)
            LoadingScreenWorldAdapter.logger
                .warning("[WARNING] loading screen model failed: \(path, privacy: .public)")
            return []
        }
    }

    public func coverView(_ gameSession: any GameSessionPort) -> FreeFlyCamera {
        gameSession.dialogueRestorePose ?? gameSession.freeFlyCamera
    }

    /// The path's camera position at `seconds`, looping over the controller's window.
    private func cameraOffset(_ frame: LoadingCoverFrame) -> SIMD3<Float> {
        guard let path = frame.cameraPath, let track = state.cameraPaths?.value(for: path) else {
            return .zero
        }
        let length = Double(track.stopTime - track.startTime)
        let local = length > 0 ? frame.elapsedSeconds.truncatingRemainder(dividingBy: length) : 0
        return track.translation(at: track.startTime + Float(local))
    }
}
