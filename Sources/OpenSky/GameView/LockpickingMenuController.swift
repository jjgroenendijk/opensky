// The lockpicking menu: opens on a refused press at a pickable lock, steps the
// `LockCoordinator` session every frame, and draws `LockpickingMenuPresentation`.
// The rules live in the coordinator. See docs/engine/locks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface

/// What `LockpickingMenuController` reads from the session. `GameViewController` conforms.
@MainActor
protocol LockpickingMenuHost: MenuInputConsumer, MenuSoundHost {
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var progression: ProgressionCoordinator { get }
    var swfMovies: SWFMovieSource { get }
    var inventoryWorld: InventoryWorldAdapter { get }
    var menuMode: MenuModeController { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var streamer: CellStreamer? { get }
}

/// Holds the open lockpicking session's input and overlay for `game`.
final class LockpickingMenuController {
    static let identifier: MenuIdentifier = "LockpickingMenu"
    /// A long frame steps as this, so a stall does not snap a pick.
    static let longestStep: Float = 0.1

    unowned let game: any LockpickingMenuHost
    private(set) var controls = LockpickingMenuControls()
    private(set) var presentation: LockpickingMenuPresentation?
    private var lastFrame: Date?
    private var wasTurning = false
    private let sounds: MenuSoundPlayer
    private lazy var movie = MenuMovieDriver<Never>(
        movies: game.swfMovies, hud: game.hud, label: "lockpicking movie"
    ) { [weak self] in self?.game.renderer }
    private var movieInfo: LockpickingMovieInfo?

    init(game: any LockpickingMenuHost) {
        self.game = game
        sounds = MenuSoundPlayer(MenuSoundDependencies(game: game))
    }

    /// The readout of the movie layer: "movie", or why the overlay draws alone.
    var movieState: String {
        if movie.isLoaded {
            return "movie"
        }
        return movie.error.map { "overlay, \($0)" } ?? "overlay"
    }

    private var locks: LockCoordinator {
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
        game.menuMode.inputConsumer = game
        game.menuMode.present(Self.identifier)
        play(.enter)
        startMovie()
        publish()
    }

    private func startMovie() {
        movieInfo = nil
        movie.start(MenuMovie(
            path: LockpickingMenuMovieBridge.moviePath,
            activate: LockpickingMenuMovieBridge.activate(runtime:),
            didLoad: { [weak self] in self?.publishMovie(force: true) }
        ), while: { [weak self] in self?.isOpen == true })
    }

    /// Opens the menu on the lock the sidebar selected, as if the player pressed on it.
    @discardableResult
    func openSelected() -> LockActionOutcome {
        guard let interaction = locks.selectedInteraction else {
            return locks.record(.noSelection)
        }
        open(InteractionTarget(
            interaction: interaction,
            hitPosition: interaction.position,
            distance: 0
        ))
        return locks.lastAction
    }

    /// Opens the menu for a lock the gate refused, if the lock can be picked.
    func handle(_ refusal: ActivationRefusalEvent) {
        guard case let .locked(level, _) = refusal.refusal else { return }
        if let notice = locks.refusalNotice(level: level) {
            locks.record(.notice(notice))
            game.hud.showNotification(locks.texts.text(for: notice))
            return
        }
        open(refusal.target)
    }

    private func close() {
        let target = locks.sessionTarget
        let opened = locks.lastOutcome?.opened == true && locks.session?.isFinished == true
        locks.closeLockpicking()
        presentation = nil
        movie.stop()
        game.gameSession?.uiScene = .empty
        game.menuMode.dismiss(Self.identifier)
        // The press that met the lock goes through now that it is open.
        if opened, let target {
            game.streamer?.activate(target)
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

    /// Steps the session by the wall-clock time since the last frame. The world is
    /// paused under the menu, so its clock does not move.
    func tick(now: Date = Date()) {
        guard isOpen, let session = locks.session else { return }
        _ = movie.tick(now: now.timeIntervalSinceReferenceDate)
        let seconds = lastFrame.map { Float(now.timeIntervalSince($0)) } ?? 0
        lastFrame = now
        let intent = controls.intent(seconds: min(seconds, Self.longestStep))
        let input = LockpickingInput(pickDelta: intent.pickDelta, turning: intent.turning)
        if intent.turning != wasTurning {
            play(intent.turning ? .cylinderTurn : .cylinderStop)
            wasTurning = intent.turning
        }
        let events = game.inventoryWorld
            .run(locks.stepLockpicking(min(seconds, Self.longestStep), input: input))
        for event in events {
            switch event {
            case .pickBroke: play(.pickBreak)
            case .opened: play(.unlock)
            case .outOfPicks, .cancelled: break
            }
        }
        guard locks.session?.isFinished != true else {
            close()
            return
        }
        publish(straining: session.isStraining(input))
    }

    private func publish(straining: Bool = false) {
        guard let session = locks.session else { return }
        let next = LockpickingMenuPresentation(
            title: locks.sessionTarget?.interaction.name ?? "Lock",
            difficulty: session.parameters.difficulty,
            pickAngle: session.pickAngle,
            halfArc: session.parameters.halfArc,
            lockRotation: session.lockRotation,
            pickHealth: session.pickHealth,
            picksRemaining: session.picksRemaining,
            isStraining: straining
        )
        guard next != presentation else { return }
        presentation = next
        game.gameSession?.uiScene = next.scene
        publishMovie()
    }

    /// The panel changes only when a pick breaks; the debug angles change every frame.
    private func publishMovie(force: Bool = false) {
        guard movie.isLoaded, let frame = presentation else { return }
        let index = ActorValueIdentity.index(named: "Lockpicking")
        let skill = game.progression.skillsMenuSkills.first { $0.index == index }
        let info = LockpickingMovieInfo(
            skillLevel: Int(skill?.level ?? 0),
            skillProgress: skill?.progress ?? 0,
            lockLevel: locks.texts.name(of: frame.difficulty),
            picksRemaining: frame.picksRemaining
        )
        let infoChanged = force || info != movieInfo
        movieInfo = info
        movie.publish { runtime in
            if infoChanged {
                LockpickingMenuMovieBridge.publish(info, runtime: runtime)
            }
            LockpickingMenuMovieBridge.publish(frame, runtime: runtime)
        }
    }

    private func play(_ sound: LockpickingSound) {
        sounds.play(editorID: sound.rawValue)
    }
}
