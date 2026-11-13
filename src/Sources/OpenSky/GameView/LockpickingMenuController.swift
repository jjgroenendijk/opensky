// The lockpicking menu: opens on a refused press at a pickable lock, steps the
// `LockCoordinator` session every frame, and draws `LockpickingMenuPresentation`.
// The rules live in the coordinator. See docs/engine/locks.md.

import Foundation
import OpenSkyCells
import OpenSkyCrime
import OpenSkyFormatsESM
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface

/// What `LockpickingMenuController` reads from the session. `GameViewController` conforms.
@MainActor
protocol LockpickingMenuHost: MenuInputConsumer, MenuSoundHost, SendableMetatype {
    var crime: any CrimePort { get }
    var hud: any HUDPort { get }
    var inventory: any InventoryPort { get }
    var swfMovies: any SWFMovieSourcePort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var menuMode: any MenuModePort { get }
    var renderer: (any RendererPort)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var streamer: any CellStreamerPort { get }
}

/// Holds the open lockpicking session's input and overlay for `game`.
final class LockpickingMenuController {
    static let identifier: MenuIdentifier = "LockpickingMenu"
    /// A long frame steps as this, so a stall does not snap a pick.
    static let longestStep: Float = 0.1

    unowned let game: any LockpickingMenuHost
    var controls = LockpickingMenuControls()
    var presentation: LockpickingMenuPresentation?
    var lastFrame: Date?
    var wasTurning = false
    private let sounds: MenuSoundPlayer
    lazy var movie = MenuMovieDriver<Never>(
        movies: game.swfMovies, hud: game.hud, label: "lockpicking movie"
    ) { [weak self] in self?.game.renderer }
    var movieInfo: LockpickingMovieInfo?
    var lockSource: LockpickingLockSource?
    var openedAt: Date?
    /// When the pick in hand went in, so its intro plays again after a break.
    var pickStartedAt: Date?
    var brokeAt: Date?
    var drawsLockModel = false

    let boardHost: any LockpickingBoardHost

    var board: LockpickingMenuController.BoardAdapter {
        LockpickingMenuController.BoardAdapter(owner: self, game: boardHost)
    }

    init(game: some LockpickingMenuHost & LockpickingBoardHost) {
        boardHost = game
        self.game = game
        sounds = MenuSoundPlayer(MenuSoundDependencies(game: game))
    }

    var locks: any LockPort {
        game.inventory.locks
    }

    var isOpen: Bool {
        presentation != nil
    }

    // MARK: - Lifecycle

    /// Starts picking `target`. A refusal leaves the menu shut; the coordinator's
    /// last text says why.
    func open(_ target: InteractionTarget) {
        guard !isOpen else { return }
        do {
            try locks.beginLockpicking(target)
        } catch {
            locks.record(.pickRefused(error, name: target.interaction.name))
            return
        }
        controls = LockpickingMenuControls()
        lastFrame = nil
        wasTurning = false
        let now = Date()
        openedAt = now
        pickStartedAt = now
        brokeAt = nil
        game.menuMode.inputConsumer = game
        game.menuMode.present(Self.identifier)
        play(.enter)
        startMovie()
        board.publish()
    }

    func startMovie() {
        movieInfo = nil
        movie.start(MenuMovie(
            path: LockpickingMenuMovieBridge.moviePath,
            activate: LockpickingMenuMovieBridge.activate(runtime:),
            didLoad: { [weak self] in self?.board.publishMovie(force: true) }
        ), while: { [weak self] in self?.isOpen == true })
    }

    /// Opens the menu for a lock the gate refused, if the lock can be picked.
    func handle(_ refusal: ActivationRefusalEvent) {
        guard case let .locked(level, _) = refusal.refusal else { return }
        if let notice = locks.refusalNotice(level: level, pursued: game.crime.isPlayerPursued) {
            locks.record(.notice(notice))
            game.hud.showNotification(locks.texts.text(for: notice))
            return
        }
        open(refusal.target)
    }

    func close() {
        let target = locks.sessionTarget
        let opened = locks.lastOutcome?.opened == true && locks.session?.isFinished == true
        locks.closeLockpicking()
        presentation = nil
        movie.stop()
        if drawsLockModel {
            game.renderer?.setMenuScene(nil)
            drawsLockModel = false
        }
        game.gameSession?.uiScene = .empty
        game.menuMode.dismiss(Self.identifier)
        // The press that met the lock goes through now that it is open.
        if opened, let target {
            game.streamer.residents.activate(target)
        }
    }

    // MARK: - Input and frames

    func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        controls.handle(event)
        guard controls.cancelRequested else { return }
        game.inventoryWorld.run(locks.cancelLockpicking())
        close()
    }

    func play(_ sound: LockpickingSound) {
        sounds.play(editorID: sound.rawValue)
    }
}
