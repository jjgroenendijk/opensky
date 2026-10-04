// World > Camera > Kill Cam: the seam the sidebar reads and the readout lines.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct CinematicCameraSnapshot: Equatable, Sendable {
    public var isAvailable = false
    public var killCamsEnabled = true
    public var shotNames: [String] = []
    public var activeShot: String?
    public var stage = 0
    public var stageCount = 0
    public var remainingSeconds: Double = 0
    public var timeScale: Float = 1
    public var playedCount = 0
    public var isShaking = false
    public var lastOutcome: String?
    /// One line per camera path the last walk visited, indented by depth.
    public var pathLines: [String] = []

    public init() {}

    public static let unavailable = CinematicCameraSnapshot()
}

public protocol CinematicCameraControlProviding: AnyObject {
    var cinematicSnapshot: CinematicCameraSnapshot { get }
    var killCamsEnabled: Bool { get set }
    /// Plays one CAMS from the player toward the selected actor.
    func playCameraShot(editorID: String)
    /// Picks a kill cam for the selected actor as if the player had just killed it.
    func playKillCamOnSelected()
    func stopCinematicCamera()
    func shakeCamera()
}

extension CinematicCameraCoordinator {
    public var snapshot: CinematicCameraSnapshot {
        var snapshot = CinematicCameraSnapshot()
        snapshot.isAvailable = cameraShotNames != nil
        snapshot.killCamsEnabled = settings.enabled
        snapshot.shotNames = cameraShotNames ?? []
        if let player, let stage = player.currentStage, !player.isFinished {
            snapshot.activeShot = stage.shot.record.editorID ?? stage.shot.id.description
            snapshot.stage = player.stageIndex + 1
            snapshot.stageCount = player.stages.count
            snapshot.remainingSeconds = player.remainingSeconds
            snapshot.timeScale = player.worldTimeScale
        }
        snapshot.playedCount = playedCount
        snapshot.isShaking = shake != nil
        snapshot.lastOutcome = lastOutcome
        snapshot.pathLines = lastSelection.trace.map(CinematicCameraReadout.pathLine)
        return snapshot
    }

    var cameraShotNames: [String]? {
        world.flatMap { $0.cameraPaths?.shots.records.compactMap(\.record.editorID).sorted() }
    }
}

nonisolated public enum CinematicCameraReadout {
    public static func text(for snapshot: CinematicCameraSnapshot) -> String {
        guard snapshot.isAvailable else { return "Kill cams: no game data" }
        var lines = [shotLine(snapshot), "Kill cams played: \(snapshot.playedCount)"]
        if snapshot.isShaking {
            lines.append("Camera shake: on")
        }
        if let outcome = snapshot.lastOutcome {
            lines.append("Last: \(outcome)")
        }
        if !snapshot.pathLines.isEmpty {
            lines.append("Paths:")
            lines += snapshot.pathLines
        }
        return lines.joined(separator: "\n")
    }

    static func shotLine(_ snapshot: CinematicCameraSnapshot) -> String {
        guard let shot = snapshot.activeShot else { return "Shot: none" }
        return "Shot: \(shot) (\(snapshot.stage) of \(snapshot.stageCount)), "
            + String(
                format: "%.1f s left, time scale %.2f",
                snapshot.remainingSeconds,
                snapshot.timeScale
            )
    }

    static func pathLine(_ trace: CameraPathTrace) -> String {
        let indent = String(repeating: "  ", count: trace.depth + 1)
        let name = trace.editorID ?? trace.id.description
        return indent + name + ": " + verdictText(trace.verdict)
    }

    static func verdictText(_ verdict: CameraPathTrace.Verdict) -> String {
        switch verdict {
        case .chosen: "chosen"
        case .passed: "passes"
        case let .rejected(function): "fails \(function)"
        case .notReached: "not reached"
        case .noShots: "passes, no shots"
        }
    }
}

/// Lets the app's provider stand in for its coordinator, one line to conform.
public protocol CinematicCameraControlForwarding: CinematicCameraControlProviding {
    var cinematicCamera: CinematicCameraCoordinator { get }
    /// The actor the sidebar acts on, or nil when none is near.
    var cinematicSelectedActor: ReferenceKey? { get }
    var cinematicRemainingHostiles: Int { get }
}

extension CinematicCameraControlForwarding {
    public var cinematicSnapshot: CinematicCameraSnapshot {
        cinematicCamera.inspectPaths(attacker: .player, target: cinematicSelectedActor)
        return cinematicCamera.snapshot
    }

    public var killCamsEnabled: Bool {
        get { cinematicCamera.settings.enabled }
        set { cinematicCamera.settings.enabled = newValue }
    }

    public func playCameraShot(editorID: String) {
        cinematicCamera.playShot(
            editorID: editorID,
            attacker: .player,
            target: cinematicSelectedActor
        )
    }

    public func playKillCamOnSelected() {
        guard let target = cinematicSelectedActor else { return }
        cinematicCamera.playKillCam(
            attacker: .player, target: target, remainingHostiles: cinematicRemainingHostiles,
            force: true
        )
    }

    public func stopCinematicCamera() {
        cinematicCamera.stop()
    }

    public func shakeCamera() {
        cinematicCamera.startShake(source: nil, strength: 1, duration: 1)
    }
}
