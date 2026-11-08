import Foundation
public import OpenSkyCells
public import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyGameData
public import OpenSkyLoading
import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkySession
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
    public unowned let owner: LoadingScreenWorldAdapter
    public unowned let game: any LoadingScreenPresentationHost
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
        if owner.movieText != text {
            startMovie(text: text)
        }
        if !frame.drawsObject, !owner.movieFadedOut, owner.movie.isLoaded {
            owner.movieFadedOut = true
            attempt { try game.renderer?.updateSWFOverlay(LoadingMenuMovieBridge.fadeOut(runtime:))
            }
        }
    }

    public func startMovie(text: String) {
        owner.movieText = text
        owner.movieFadedOut = false
        let content = movieContent(text: text)
        owner.movie.start(
            path: LoadingMenuMovieBridge.moviePath,
            prepare: { [weak owner] runtime in
                LoadingMenuMovieBridge.prepare(runtime: runtime) { owner?.movieText ?? "" }
            },
            activate: { LoadingMenuMovieBridge.activate(runtime: $0, content: content) }
        )
    }

    public var isMovieLoaded: Bool {
        owner.movie.isLoaded
    }

    private func stopMovie() {
        guard owner.movieText != nil else { return }
        owner.movieText = nil
        owner.movie.stop()
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
                let view = owner.coverView(gameSession)
                try renderer.setLoadingCover(
                    owner.placement(frame, gameSession: gameSession),
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
        gameSession.uiScene = frame?.overlay(showsText: !owner.movie.isLoaded) ?? .empty
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
