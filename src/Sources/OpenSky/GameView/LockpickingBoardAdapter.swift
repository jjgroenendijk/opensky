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

/// What `LockpickingMenuController.BoardAdapter` reads from the session.
@MainActor
protocol LockpickingBoardHost: AnyObject {
    var gameSession: (any GameSessionPort)? { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var progression: any ProgressionPort { get }
    var renderer: (any RendererPort)? { get }
    var worldData: WorldDataStores? { get }
}

extension LockpickingMenuController {
    /// Part of `LockpickingMenuController`, over its own narrow host.
    struct BoardAdapter {
        unowned let owner: LockpickingMenuController
        unowned let game: any LockpickingBoardHost
    }
}

extension LockpickingMenuController.BoardAdapter {
    /// Steps the session by the wall-clock time since the last frame. The world is
    /// paused under the menu, so its clock does not move.
    func tick(now: Date = Date()) {
        guard owner.isOpen, let session = owner.locks.session else { return }
        _ = owner.movie.tick(now: now.timeIntervalSinceReferenceDate)
        let seconds = owner.lastFrame.map { Float(now.timeIntervalSince($0)) } ?? 0
        owner.lastFrame = now
        let intent = owner.controls.intent(seconds: min(
            seconds,
            LockpickingMenuController.longestStep
        ))
        let input = LockpickingInput(pickDelta: intent.pickDelta, turning: intent.turning)
        if intent.turning != owner.wasTurning {
            owner.play(intent.turning ? .cylinderTurn : .cylinderStop)
            owner.wasTurning = intent.turning
        }
        let events = game.inventoryWorld
            .run(owner.locks.stepLockpicking(
                min(seconds, LockpickingMenuController.longestStep),
                input: input
            ))
        for event in events {
            switch event {
            case .pickBroke:
                owner.play(.pickBreak)
                owner.brokeAt = now
            case .opened: owner.play(.unlock)
            case .outOfPicks, .cancelled: break
            }
        }
        guard owner.locks.session?.isFinished != true else {
            owner.close()
            return
        }
        if
            let brokeAt = owner.brokeAt,
            now.timeIntervalSince(brokeAt) > Double(LockpickingLockPose.breakSeconds)
        {
            owner.brokeAt = nil
            owner.pickStartedAt = now
        }
        publish(straining: session.isStraining(input))
        drawLock(now: now)
    }

    /// Draws the install's lock and pick in the menu scene once both meshes are in.
    private func drawLock(now: Date) {
        guard let frame = owner.presentation, let renderer = game.renderer else { return }
        if owner.lockSource == nil, let files = game.worldData?.scriptFileSystem {
            owner.lockSource = LockpickingLockSource(fileSystem: files)
        }
        guard let models = owner.lockSource?.models(device: renderer.device) else { return }
        func seconds(since date: Date?) -> Float {
            Float(date.map { now.timeIntervalSince($0) } ?? 0)
        }
        let pose = LockpickingLockPose(
            pickSeconds: seconds(since: owner.pickStartedAt),
            lockSeconds: seconds(since: owner.openedAt),
            pickAngle: frame.pickAngle, lockRotation: frame.lockRotation,
            isStraining: frame.isStraining,
            brokenSeconds: owner.brokeAt == nil ? nil : seconds(since: owner.brokeAt)
        )
        renderer.setMenuScene(LockpickingLockSource.scene(pose, models: models))
        guard !owner.drawsLockModel else { return }
        owner.drawsLockModel = true
        publish(straining: frame.isStraining)
    }

    func publish(straining: Bool = false) {
        guard let session = owner.locks.session else { return }
        let next = LockpickingMenuPresentation(
            title: owner.locks.sessionTarget?.interaction.name ?? "Lock",
            difficulty: session.parameters.difficulty,
            pickAngle: session.pickAngle,
            halfArc: session.parameters.halfArc,
            lockRotation: session.lockRotation,
            pickHealth: session.pickHealth,
            picksRemaining: session.picksRemaining,
            isStraining: straining,
            drawsLockModel: owner.drawsLockModel
        )
        guard next != owner.presentation else { return }
        owner.presentation = next
        game.gameSession?.uiScene = next.scene
        publishMovie()
    }

    /// The readout changes only when a pick breaks; the debug angles change every frame.
    func publishMovie(force: Bool = false) {
        guard owner.movie.isLoaded, let frame = owner.presentation else { return }
        let index = ActorValueIdentity.index(named: "Lockpicking")
        let skill = game.progression.skillsMenuSkills.first { $0.index == index }
        let info = LockpickingMovieInfo(
            skillLevel: Int(skill?.level ?? 0),
            skillProgress: skill?.progress ?? 0,
            lockLevel: owner.locks.texts.name(of: frame.difficulty),
            picksRemaining: frame.picksRemaining
        )
        let infoChanged = force || info != owner.movieInfo
        owner.movieInfo = info
        owner.movie.publish { runtime in
            if infoChanged {
                LockpickingMenuMovieBridge.publish(info, runtime: runtime)
            }
            LockpickingMenuMovieBridge.publish(frame, runtime: runtime)
        }
    }
}
