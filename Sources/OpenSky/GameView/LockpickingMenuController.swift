// The lockpicking menu: opens on a refused press at a pickable lock, steps the
// `LockCoordinator` session every frame, and draws `LockpickingMenuPresentation`.
// The rules live in the coordinator. See docs/engine/locks.md.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface

/// Holds the open lockpicking session's input and overlay for `game`.
final class LockpickingMenuController {
    static let identifier: MenuIdentifier = "LockpickingMenu"
    /// A long frame steps as this, so a stall does not snap a pick.
    static let longestStep: Float = 0.1

    unowned let game: GameViewController
    private(set) var controls = LockpickingMenuControls()
    private(set) var presentation: LockpickingMenuPresentation?
    private var lastFrame: Date?
    private var wasTurning = false

    init(game: GameViewController) {
        self.game = game
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
            locks.note(Self.describe(error, name: target.interaction.name))
            return
        }
        controls = LockpickingMenuControls()
        lastFrame = nil
        wasTurning = false
        game.menuMode.inputConsumer = game
        game.menuMode.present(Self.identifier)
        play(.enter)
        publish()
    }

    /// Opens the menu on the lock the sidebar selected, as if the player pressed on it.
    @discardableResult
    func openSelected() -> String {
        guard let interaction = locks.selectedInteraction else {
            return locks.note("No lock selected.")
        }
        open(InteractionTarget(
            interaction: interaction,
            hitPosition: interaction.position,
            distance: 0
        ))
        return locks.lastText
    }

    /// Opens the menu for a lock the gate refused, if the lock can be picked.
    func handle(_ refusal: ActivationRefusalEvent) {
        guard
            case let .locked(level, _) = refusal.refusal,
            LockDifficulty(level: level).isPickable,
            locks.lockpickCount > 0
        else { return }
        open(refusal.target)
    }

    private func close() {
        let target = locks.sessionTarget
        let opened = locks.lastOutcome?.opened == true && locks.session?.isFinished == true
        locks.closeLockpicking()
        presentation = nil
        game.renderer?.uiScene = .empty
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
        locks.cancelLockpicking()
        close()
    }

    /// Steps the session by the wall-clock time since the last frame. The world is
    /// paused under the menu, so its clock does not move.
    func tick(now: Date = Date()) {
        guard isOpen, let session = locks.session else { return }
        let seconds = lastFrame.map { Float(now.timeIntervalSince($0)) } ?? 0
        lastFrame = now
        let intent = controls.intent(seconds: min(seconds, Self.longestStep))
        let input = LockpickingInput(pickDelta: intent.pickDelta, turning: intent.turning)
        if intent.turning != wasTurning {
            play(intent.turning ? .cylinderTurn : .cylinderStop)
            wasTurning = intent.turning
        }
        let events = locks.stepLockpicking(min(seconds, Self.longestStep), input: input)
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
        game.renderer?.uiScene = next.scene
    }

    // MARK: - Sound

    /// Plays a lockpicking `SNDR` at the camera. A missing record stays silent.
    private func play(_ sound: LockpickingSound) {
        guard
            let renderer = game.renderer,
            let engine = renderer.worldAudio, engine.isRunning,
            let sounds = (game.worldData as? AudioDataProviding)?.soundStore,
            let descriptor = sounds.descriptors.values.first(where: {
                $0.editorID?.caseInsensitiveCompare(sound.rawValue) == .orderedSame
            }),
            let resolved = try? sounds.resolveAny(descriptor.formID),
            let path = resolved.filePaths.first,
            let data = try? game.audioFileSystem?.contents(forPath: path)
        else { return }
        _ = try? engine.playPositional(
            fileData: data,
            request: AudioPlayRequest(
                name: path,
                category: resolved.audioCategory ?? .effects,
                worldPosition: renderer.freeFlyCamera.position
            )
        )
    }

    static func describe(_ refusal: any Error, name: String) -> String {
        switch refusal as? LockpickingRefusal {
        case .noLockpicks: "\(name) is locked and you have no lockpicks."
        case .requiresKey: "\(name) requires a key."
        case .notLocked: "\(name) is not locked."
        case .noRuntime, .unknownReference, nil: "\(name) cannot be picked."
        }
    }
}
