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
    public var settings = HeadTrackingSettings.vanilla
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
        let isDialogue: Bool
    }

    private var targets: [ReferenceKey: HeldTarget] = [:]
    /// Actors whose clip sent `HeadTrackingOff`: they look ahead until `HeadTrackingOn`.
    public private(set) var heldForward: Set<ReferenceKey> = []
    private var clock: Float = 0
    /// Heads still turning toward their goal; the rest wait out the dead zone.
    private var turning: Set<ReferenceKey> = []
    /// When each actor last had the player within its notice distance.
    private var lastNoticed: [ReferenceKey: Float] = [:]
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

    /// Makes `actor` look at `target`, or with nil hands it back to the default. With
    /// `seconds`, the target lets go on its own. In `dialogue` the speaker glances by the
    /// dialogue settings.
    public func setLookTarget(
        _ target: ReferenceKey?, for actor: ReferenceKey, seconds: Float? = nil,
        dialogue: Bool = false
    ) {
        targets[actor] = target.map {
            HeldTarget(target: $0, until: seconds.map { clock + $0 }, isDialogue: dialogue)
        }
    }

    /// A clip's `HeadTrackingOff` holds the head forward, so an attack aims where the body
    /// faces; `HeadTrackingOn` lets it turn again.
    public func setHeadTracking(_ enabled: Bool, for actor: ReferenceKey) {
        if enabled {
            heldForward.remove(actor)
        } else {
            heldForward.insert(actor)
        }
    }

    public func tick(deltaTime: Float) {
        clock += max(deltaTime, 0)
        targets = targets.filter { $0.value.until.map { $0 > clock } ?? true }
        guard isEnabled, let world else { return }
        var nextLooks: [ReferenceKey: HeadLook] = [:]
        var nextTargets: [ReferenceKey: ReferenceKey] = [:]
        let player = world.headPosition(of: .player)
        for subject in world.headTrackingSubjects {
            let target = chosenTarget(of: subject, player: player)
            let aim = target.flatMap { key in
                world.headPosition(of: key).flatMap { look(of: subject, toward: $0) }
            }
            let goal = aim.map { withGlance($0, subject: subject.key) } ?? .forward
            let step = HeadTrackingCore.turn(
                looks[subject.key] ?? .forward, toward: goal,
                isTurning: turning.contains(subject.key) || aim == nil,
                deltaTime: deltaTime, settings: settings
            )
            if step.isTurning {
                turning.insert(subject.key)
            } else {
                turning.remove(subject.key)
            }
            subject.playback.headLook = step.look
            nextLooks[subject.key] = step.look
            nextTargets[subject.key] = aim == nil ? nil : target
        }
        looks = nextLooks
        lookTargets = nextTargets
        turning.formIntersection(nextLooks.keys)
        lastNoticed = lastNoticed.filter { clock - $0.value <= settings.holdDefault }
    }

    private func withGlance(_ aim: HeadLook, subject: ReferenceKey) -> HeadLook {
        let timing = targets[subject]?.isDialogue == true ? settings.dialogue : settings.idle
        let seed: UInt32 = switch subject {
        case let .plugin(_, objectID): objectID
        case let .generated(number): UInt32(truncatingIfNeeded: number)
        }
        let spread = Float(seed % 1000) / 1000 * timing.resetPosition
        let glance = HeadTrackingCore.glance(at: clock + spread, seed: seed, timing: timing)
        guard glance != .forward else { return aim }
        return HeadTrackingCore.limited(
            HeadLook(yaw: aim.yaw + glance.yaw, pitch: aim.pitch + glance.pitch),
            settings: settings
        )
    }

    private func chosenTarget(
        of subject: HeadTrackingSubject,
        player: SIMD3<Float>?
    ) -> ReferenceKey? {
        guard !heldForward.contains(subject.key) else { return nil }
        if let held = targets[subject.key] {
            return held.target
        }
        guard subject.key != .player, let player else { return nil }
        let origin = subject.worldFromActor.columns.3
        let distance = simd_distance(SIMD2(origin.x, origin.y), SIMD2(player.x, player.y))
        if distance <= Self.noticeDistance {
            lastNoticed[subject.key] = clock
        }
        return lastNoticed[subject.key] != nil ? .player : nil
    }

    private func look(of subject: HeadTrackingSubject, toward point: SIMD3<Float>) -> HeadLook? {
        let local = subject.worldFromActor.inverse * SIMD4(point, 1)
        return HeadTrackingCore.look(
            from: SIMD3(0, 0, Self.eyeHeight), at: SIMD3(local.x, local.y, local.z),
            settings: settings
        )
    }
}
