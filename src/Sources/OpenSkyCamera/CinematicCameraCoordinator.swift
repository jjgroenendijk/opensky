// Kill cams and camera shake: picks a shot sequence through the camera paths,
// plays it over the player's view with the shot's world time scale, and adds
// script shakes on top. See docs/engine/kill-cam.md.

import Foundation
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyFormatsMesh
public import OpenSkyGameData
public import OpenSkyWorldInterface
import simd

/// What the cinematic camera needs from the app.
public protocol CinematicCameraWorld: AnyObject {
    var cameraPaths: CameraPathStore? { get }
    func cameraConditionContext() -> ConditionContext
    /// The weapon and free-space facts the path conditions read for this pair.
    /// `projectile` is the live shot a ranged kill cam follows, or nil for a melee kill.
    func cameraShotFacts(
        attacker: ReferenceKey, target: ReferenceKey?, projectile: Int?
    ) -> CameraConditionResolution
    /// The camera track in a CAMS model, or nil when the model has none.
    func cameraTrack(model: String) -> NIFCameraTrack?
    /// Where an actor stands and faces, or nil when it is not loaded.
    func cinematicAnchor(of key: ReferenceKey) -> CinematicAnchor?
    var playerPosition: SIMD3<Float>? { get }
    @discardableResult
    func startImageSpaceModifier(_ key: ReferenceKey) -> Bool
    /// Where a projectile in flight is and faces; nil once its impact is resolved.
    func cinematicProjectileAnchor(_ id: Int) -> CinematicAnchor?
    func cinematicTargetIsDead(_ key: ReferenceKey) -> Bool
}

extension CinematicCameraWorld {
    public func cinematicProjectileAnchor(_: Int) -> CinematicAnchor? {
        nil
    }

    public func cinematicTargetIsDead(_: ReferenceKey) -> Bool {
        true
    }
}

/// The time limits of a kill cam that follows a projectile.
nonisolated public enum RangedKillCamLimits {
    public static let longestSeconds = 20.0
    /// While the target still lives, as when the shot misses after all.
    public static let longestWhileAliveSeconds = 6.0

    /// Whether a shot `elapsed` real seconds old must end.
    public static func ends(elapsed: Double, targetIsDead: Bool) -> Bool {
        elapsed >= longestSeconds || (!targetIsDead && elapsed >= longestWhileAliveSeconds)
    }
}

public final class CinematicCameraCoordinator {
    /// The longest real step one frame advances a shot by, so a stall does not skip it.
    public static let longestFrameSeconds = 0.1
    public let settings: KillCamSettings
    public private(set) var player: CinematicShotPlayer?
    public private(set) var attacker: ReferenceKey?
    public private(set) var target: ReferenceKey?
    public private(set) var lastSelection = CameraShotSelection.none
    /// Why the last kill cam played or did not.
    public private(set) var lastOutcome: String?
    public private(set) var shake: CameraShake?
    public private(set) var time: Double = 0
    public private(set) var playedCount = 0
    /// The projectile a ranged kill cam follows, until its impact.
    public private(set) var projectile: Int?
    /// Targets whose kill cam was decided at a release, so their death starts no second one.
    public private(set) var rangedTargets: Set<ReferenceKey> = []
    private var shotSeconds: Double = 0
    private var isRangedShot = false
    private var random = ConditionRandom()
    weak let world: (any CinematicCameraWorld)?

    public init(world: any CinematicCameraWorld, settings: KillCamSettings = KillCamSettings()) {
        self.world = world
        self.settings = settings
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
        return startKillCam(attacker: attacker, target: target, projectile: nil)
    }

    private func startKillCam(
        attacker: ReferenceKey, target: ReferenceKey, projectile shot: Int?
    ) -> Bool {
        guard
            let world,
            let store = world.cameraPaths else { return note("no camera paths loaded") }
        let check = pathCheck(world, attacker: attacker, target: target, projectile: shot)
        lastSelection = CameraShotSelector(store: store, check: check).select(random: &random)
        let stages = lastSelection.sequence.map { shot in
            CinematicStage(
                shot: shot,
                track: shot.record.model.flatMap { world.cameraTrack(model: $0.path) }
            )
        }.filter { $0.duration > 0 }
        guard !stages.isEmpty else {
            return note(lastSelection.path.map {
                "the path \($0.record.editorID ?? "?") asks for no kill cam"
            } ?? "no camera path passed its conditions")
        }
        self.attacker = attacker
        self.target = target
        projectile = nil
        shotSeconds = 0
        isRangedShot = false
        player = CinematicShotPlayer(stages: stages)
        playedCount += 1
        startStageEffects()
        return note(
            "playing \(stages.count) shots from \(lastSelection.path?.record.editorID ?? "a path")"
        )
    }

    /// The release check passed for the player's shot `projectile`, which will kill `target`:
    /// the kill cam follows the projectile. The check already did the odds and the enemy count.
    @discardableResult
    public func playRangedKillCam(projectile id: Int, target: ReferenceKey) -> Bool {
        rangedTargets.insert(target)
        guard !isPlaying else { return note("a kill cam already plays") }
        guard startKillCam(attacker: .player, target: target, projectile: id) else { return false }
        projectile = id
        isRangedShot = true
        return true
    }

    /// Whether a death should leave its kill cam to the one its release decided.
    public func killCamWasDecided(for target: ReferenceKey) -> Bool {
        rangedTargets.remove(target) != nil
    }

    private func pathCheck(
        _ world: any CinematicCameraWorld, attacker: ReferenceKey, target: ReferenceKey?,
        projectile: Int?
    ) -> CameraShotSelector.Check {
        var context = world.cameraConditionContext()
        context.camera = world.cameraShotFacts(
            attacker: attacker, target: target, projectile: projectile
        )
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
            shotSeconds += max(0, realSeconds)
            if let id = projectile, world?.cinematicProjectileAnchor(id) == nil {
                // The impact is resolved: the fly stage ends and the camera leaves the shot.
                projectile = nil
                current.endStageEarly()
            }
            player = current
            if current.isFinished || rangedShotEnds() {
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
            target: target.flatMap { world.cinematicAnchor(of: $0) },
            projectile: projectile.flatMap { world.cinematicProjectileAnchor($0) }
        )
    }

    private func rangedShotEnds() -> Bool {
        guard isRangedShot, let target else { return false }
        return RangedKillCamLimits.ends(
            elapsed: shotSeconds, targetIsDead: world?.cinematicTargetIsDead(target) ?? true
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
        projectile = nil
        shotSeconds = 0
        isRangedShot = false
    }

    @discardableResult
    private func note(_ text: String) -> Bool {
        lastOutcome = text
        return player != nil && text.hasPrefix("playing")
    }
}
