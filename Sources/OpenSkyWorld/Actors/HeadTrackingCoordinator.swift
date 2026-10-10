// Chooses what each loaded actor looks at and eases its head there: a given target,
// such as the player in a conversation or a scene's `HTID` alias, else the player
// when near. See docs/engine/head-tracking.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// One loaded actor that can turn its head.
public struct HeadTrackingSubject {
    public let key: ReferenceKey
    public let playback: ActorAnimationPlayback
    /// The drawn transform: the actor's skeleton frame to world space.
    public let worldFromActor: float4x4

    public init(key: ReferenceKey, playback: ActorAnimationPlayback, worldFromActor: float4x4) {
        self.key = key
        self.playback = playback
        self.worldFromActor = worldFromActor
    }
}

/// What `HeadTrackingCoordinator` reads from the running world.
public protocol HeadTrackingWorld: AnyObject {
    /// Living, drawn actors with a skeleton.
    var headTrackingSubjects: [HeadTrackingSubject] { get }
    /// Where `key`'s eyes are in world space, the player included. Nil when not loaded.
    func headPosition(of key: ReferenceKey) -> SIMD3<Float>?
}

public final class HeadTrackingCoordinator {
    /// An actor this near the player looks at the player when nothing else holds its eye.
    public static let noticeDistance: Float = 384
    /// Eye height in the skeleton frame, before the actor's scale.
    public static let eyeHeight: Float = 120

    weak var world: (any HeadTrackingWorld)?
    public var isEnabled = true {
        didSet {
            guard !isEnabled else { return }
            for subject in world?.headTrackingSubjects ?? [] {
                subject.playback.headLook = .forward
            }
        }
    }

    private struct HeldTarget {
        let target: ReferenceKey
        let until: Float?
    }

    private var targets: [ReferenceKey: HeldTarget] = [:]
    private var clock: Float = 0
    public private(set) var looks: [ReferenceKey: HeadLook] = [:]
    /// The target each actor looked at in the last tick, for the readout.
    public private(set) var lookTargets: [ReferenceKey: ReferenceKey] = [:]

    /// `settings` gives the persisted head tracking switch.
    public init(world: (any HeadTrackingWorld)? = nil, settings: PlayerSettingsStore? = nil) {
        self.world = world
        if let settings {
            isEnabled = settings.bool(.characterHeadTracking)
        }
    }

    public func attach(world: any HeadTrackingWorld) {
        self.world = world
    }

    /// One panel line: what `actor` looks at and how far its head turns.
    public func readout(for actor: ReferenceKey?) -> String {
        guard let actor else { return "no selected actor" }
        let look = looks[actor] ?? .forward
        let target = lookTargets[actor].map { "\($0)" } ?? "ahead"
        return String(
            format: "looks at %@, yaw %.0f°, pitch %.0f°",
            target, look.yaw * 180 / .pi, look.pitch * 180 / .pi
        )
    }

    /// Makes `actor` look at `target`, or with nil hands it back to the default. With
    /// `seconds`, the target lets go on its own.
    public func setLookTarget(
        _ target: ReferenceKey?, for actor: ReferenceKey, seconds: Float? = nil
    ) {
        targets[actor] = target.map { HeldTarget(target: $0, until: seconds.map { clock + $0 }) }
    }

    public func tick(deltaTime: Float) {
        clock += max(deltaTime, 0)
        targets = targets.filter { $0.value.until.map { $0 > clock } ?? true }
        guard isEnabled, let world else { return }
        let step = HeadTrackingCore.turnSpeed * max(deltaTime, 0)
        var nextLooks: [ReferenceKey: HeadLook] = [:]
        var nextTargets: [ReferenceKey: ReferenceKey] = [:]
        let player = world.headPosition(of: .player)
        for subject in world.headTrackingSubjects {
            let target = chosenTarget(of: subject, player: player)
            let goal = target.flatMap { key in
                world.headPosition(of: key).flatMap { look(of: subject, toward: $0) }
            } ?? .forward
            let look = HeadTrackingCore.approach(
                looks[subject.key] ?? .forward, goal, step: step
            )
            subject.playback.headLook = look
            nextLooks[subject.key] = look
            nextTargets[subject.key] = goal == .forward ? nil : target
        }
        looks = nextLooks
        lookTargets = nextTargets
    }

    private func chosenTarget(
        of subject: HeadTrackingSubject,
        player: SIMD3<Float>?
    ) -> ReferenceKey? {
        if let held = targets[subject.key] {
            return held.target
        }
        guard subject.key != .player, let player else { return nil }
        let origin = subject.worldFromActor.columns.3
        let distance = simd_distance(SIMD2(origin.x, origin.y), SIMD2(player.x, player.y))
        return distance <= Self.noticeDistance ? .player : nil
    }

    private func look(of subject: HeadTrackingSubject, toward point: SIMD3<Float>) -> HeadLook? {
        let local = subject.worldFromActor.inverse * SIMD4(point, 1)
        return HeadTrackingCore.look(
            from: SIMD3(0, 0, Self.eyeHeight), at: SIMD3(local.x, local.y, local.z)
        )
    }
}
