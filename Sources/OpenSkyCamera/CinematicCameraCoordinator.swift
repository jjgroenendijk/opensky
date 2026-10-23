// Kill cams and camera shake: picks a shot sequence through the camera paths,
// plays it over the player's view with the shot's world time scale, and adds
// script shakes on top. See docs/engine/kill-cam.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyWorldConditions
import simd

/// What the cinematic camera needs from the app.
public protocol CinematicCameraWorld: AnyObject {
    var cameraPaths: CameraPathStore? { get }
    func cameraConditionContext() -> ConditionContext
    /// The weapon and free-space facts the path conditions read for this pair.
    func cameraShotFacts(attacker: ReferenceKey, target: ReferenceKey?) -> CameraConditionResolution
    /// The camera track in a CAMS model, or nil when the model has none.
    func cameraTrack(model: String) -> NIFCameraTrack?
    /// Where an actor stands and faces, or nil when it is not loaded.
    func cinematicAnchor(of key: ReferenceKey) -> CinematicAnchor?
    var playerPosition: SIMD3<Float>? { get }
    @discardableResult
    func startImageSpaceModifier(_ key: ReferenceKey) -> Bool
}

/// One frame's override pose, shake, and world time scale, which the app writes.
nonisolated public struct CinematicFrame: Equatable, Sendable {
    /// Nil while no shot plays, so the player's own view shows.
    public let pose: CinematicCameraPose?
    public let shake: SIMD3<Float>
    public let timeScale: Float

    public init(pose: CinematicCameraPose?, shake: SIMD3<Float>, timeScale: Float) {
        self.pose = pose
        self.shake = shake
        self.timeScale = timeScale
    }
}

public final class CinematicCameraCoordinator {
    public var settings = KillCamSettings()
    public private(set) var player: CinematicShotPlayer?
    public private(set) var attacker: ReferenceKey?
    public private(set) var target: ReferenceKey?
    public private(set) var lastSelection = CameraShotSelection.none
    public private(set) var lastOutcome: String?
    public private(set) var shake: CameraShake?
    public private(set) var time: Double = 0
    public private(set) var playedCount = 0
    private var random = ConditionRandom()
    weak let world: (any CinematicCameraWorld)?

    public init(world: any CinematicCameraWorld) {
        self.world = world
    }

    public var isPlaying: Bool {
        player.map { !$0.isFinished } ?? false
    }

    /// Picks and starts a kill cam on `target`. `force` skips the odds and the
    /// last-enemy rule, for state reads.
    @discardableResult
    public func playKillCam(
        attacker: ReferenceKey, target: ReferenceKey, remainingHostiles: Int, force: Bool = false
    ) -> Bool {
        guard
            force || KillCamTrigger.shouldPlay(
                settings: settings, remainingHostiles: remainingHostiles, random: &random
            )
        else {
            return note("no kill cam: odds or other enemies left")
        }
        guard
            let world,
            let store = world.cameraPaths else { return note("no camera paths loaded") }
        let check = pathCheck(world, attacker: attacker, target: target)
        lastSelection = CameraShotSelector(store: store, check: check).select(random: &random)
        let stages = lastSelection.sequence.map { shot in
            CinematicStage(
                shot: shot,
                track: shot.record.model.flatMap { world.cameraTrack(model: $0.path) }
            )
        }.filter { $0.duration > 0 }
        guard !stages.isEmpty else {
            return note(lastSelection
                .path == nil ? "no camera path passed its conditions" :
                "the path asks for no kill cam")
        }
        self.attacker = attacker
        self.target = target
        player = CinematicShotPlayer(stages: stages)
        playedCount += 1
        startStageEffects()
        return note(
            "playing \(stages.count) shots from \(lastSelection.path?.record.editorID ?? "a path")"
        )
    }

    private func pathCheck(
        _ world: any CinematicCameraWorld, attacker: ReferenceKey, target: ReferenceKey?
    ) -> CameraShotSelector.Check {
        var context = world.cameraConditionContext()
        context.camera = world.cameraShotFacts(attacker: attacker, target: target)
        return CameraShotSelector.conditionCheck(
            context: context,
            attacker: attacker,
            target: target
        )
    }

    // MARK: - Shake

    /// `source` nil shakes at full strength. A far source shakes less.
    @discardableResult
    public func startShake(source: SIMD3<Float>?, strength: Float, duration: Float) -> Bool {
        let playerPosition = world?.playerPosition
        let distance = source.flatMap { from in playerPosition.map { simd_distance(from, $0) } }
        let scaled = CameraShake.strength(strength, atDistance: distance)
        guard scaled > 0 else { return false }
        shake = CameraShake(strength: scaled, duration: Double(duration), startedAt: time)
        return true
    }

    // MARK: - Frames

    /// Advances by real seconds, so a slowed world does not slow the shot.
    public func tick(realSeconds: Double) -> CinematicFrame {
        time += max(0, realSeconds)
        var pose: CinematicCameraPose?
        if var current = player, !current.isFinished {
            let before = current.stageIndex
            current.advance(realSeconds: realSeconds)
            player = current
            if current.isFinished {
                finish()
            } else {
                if current.stageIndex != before {
                    startStageEffects()
                }
                pose = anchors().flatMap { current.pose(anchors: $0) }
            }
        }
        if let active = shake, active.isFinished(at: time) {
            shake = nil
        }
        return CinematicFrame(
            pose: pose,
            shake: shake?.offset(at: time) ?? .zero,
            timeScale: isPlaying ? player?.worldTimeScale ?? 1 : 1
        )
    }

    private func anchors() -> CinematicAnchors? {
        guard
            let world, let attacker,
            let from = world.cinematicAnchor(of: attacker) else { return nil }
        return CinematicAnchors(
            attacker: from,
            target: target.flatMap { world.cinematicAnchor(of: $0) }
        )
    }

    private func startStageEffects() {
        guard
            let shot = player?.currentStage?.shot,
            let modifier = shot.record.imageSpaceModifier,
            let link = world?.cameraPaths?.shots.link(modifier, from: shot), !link.isDangling
        else { return }
        world?.startImageSpaceModifier(ReferenceKey(resolved: link.target))
    }

    private func finish() {
        player = nil
        attacker = nil
        target = nil
    }

    @discardableResult
    private func note(_ text: String) -> Bool {
        lastOutcome = text
        return player != nil && text.hasPrefix("playing")
    }
}
