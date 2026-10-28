// What the rider asks of a ridden dragon: lock or switch a target, attack it, and land.
// The rider does not steer; the dragon circles and breathes through its graph (UESP
// "Skyrim:Dragon Riding"). Pure; the mount coordinator is the shell.
// See docs/engine/dragon-flight.md#riding.

import Foundation
import OpenSkyActorPresentation
import OpenSkyFormatsESM
import simd

/// What the ridden dragon's breath asks of its graph this step.
nonisolated public enum RiddenDragonBreathStep: Equatable, Sendable {
    /// Raise `shoutStart`: the inhale clip.
    case inhale
    /// Raise `shoutRelease`: the exhale clip, whose `Voice_SpellFire_Event` casts.
    case exhale
    /// Cast the breath at the locked target now.
    case fire
}

/// The rider's orders and the ridden flight numbers. The radii, the breath range, the
/// breath aim, and the breath interval are OpenSky's: no setting names them.
nonisolated public struct RiddenDragonOrders: Equatable, Sendable {
    public static let circleRadius: Float = 3000
    public static let attackRadius: Float = 1500
    /// The farthest a ridden dragon breathes at its target from.
    public static let breathRange: Float = 3500
    /// How far off the dragon's heading, in radians, the target may be for a breath: in
    /// front of the wings. A circling dragon has its target about 73 degrees to the side.
    public static let breathAim: Float = .pi / 2
    public static let breathInterval: Float = 6
    /// The length of `shout_flightinhale.hkx`.
    public static let inhaleSeconds: Float = 1
    /// Ours: the breath casts after this long in the exhale when no graph fires the event.
    public static let exhaleFallbackSeconds: Float = 1

    nonisolated public enum BreathPhase: Equatable, Sendable {
        case ready
        case inhaling(seconds: Float)
        case exhaling(seconds: Float)
    }

    public var landingRequested = false
    public var lockedTarget: ReferenceKey?
    public var isAttacking = false
    /// The target the last Switch Target order picked.
    public var switchedTarget: ReferenceKey?
    /// Where the dragon took off; it circles here without a target.
    public var home: SIMD3<Float>?
    public var breathCooldown: Float = 0
    public var breath = BreathPhase.ready
    /// The sneak toggle at the last step: a change is the attack key.
    public var lastSneak: Bool?

    public init() {}

    /// Lock target (the jump key): locks the target in view, or unlocks when there is
    /// none or it is the one already locked. Unlocking ends the attack.
    public mutating func lock(_ candidate: ReferenceKey?) {
        if candidate == nil || candidate == lockedTarget {
            lockedTarget = nil
            isAttacking = false
            breath = .ready
        } else {
            lockedTarget = candidate
        }
    }

    /// Switch Target (keys 1 and 2): locks the next actor in view, left to right, or the
    /// one before it. Switching calls the attack off (UESP "Skyrim:Dragon Riding").
    /// - Returns: false when nothing is in view.
    public mutating func switchTarget(among candidates: [ReferenceKey], forward: Bool) -> Bool {
        guard !candidates.isEmpty else { return false }
        let step = forward ? 1 : -1
        let next = if let current = lockedTarget.flatMap(candidates.firstIndex(of:)) {
            (current + step + candidates.count) % candidates.count
        } else {
            forward ? 0 : candidates.count - 1
        }
        lockedTarget = candidates[next]
        switchedTarget = candidates[next]
        isAttacking = false
        breath = .ready
        return true
    }

    /// Attack (the sneak key): needs a locked target. Returns false without one.
    public mutating func toggleAttack() -> Bool {
        guard lockedTarget != nil else { return false }
        isAttacking.toggle()
        return true
    }

    /// The flight goal: land when asked, circle the target when attacking, else circle
    /// home. `target` is nil once the target is dead or gone.
    public func goal(home fallback: SIMD3<Float>, target: SIMD3<Float>?) -> DragonFlightGoal {
        if landingRequested {
            return .ground(nil)
        }
        if isAttacking, let target {
            return .circle(center: target, radius: Self.attackRadius)
        }
        return .circle(center: home ?? fallback, radius: Self.circleRadius)
    }

    /// The breath's next graph step. It starts once the cooldown is over and the target
    /// is in range ahead; it casts on the exhale's `Voice_SpellFire_Event` (`fired`).
    public mutating func advanceBreath(
        from feet: SIMD3<Float>, yaw: Float, at target: SIMD3<Float>?, fired: Bool,
        deltaTime: Float
    ) -> RiddenDragonBreathStep? {
        let delta = max(deltaTime, 0)
        breathCooldown = max(0, breathCooldown - delta)
        switch breath {
        case .ready:
            guard isAttacking, let target, breathCooldown <= 0, Self.inReach(feet, yaw, target)
            else { return nil }
            breath = .inhaling(seconds: 0)
            return .inhale
        case let .inhaling(seconds):
            let elapsed = seconds + delta
            guard elapsed >= Self.inhaleSeconds else {
                breath = .inhaling(seconds: elapsed)
                return nil
            }
            breath = .exhaling(seconds: 0)
            return .exhale
        case let .exhaling(seconds):
            let elapsed = seconds + delta
            guard fired || elapsed >= Self.exhaleFallbackSeconds else {
                breath = .exhaling(seconds: elapsed)
                return nil
            }
            breath = .ready
            breathCooldown = Self.breathInterval
            return target == nil ? nil : .fire
        }
    }

    /// In range, and ahead of the dragon within the breath aim.
    static func inReach(_ feet: SIMD3<Float>, _ yaw: Float, _ target: SIMD3<Float>) -> Bool {
        guard simd_distance(feet, target) <= breathRange else { return false }
        let offset = SIMD2(target.x - feet.x, target.y - feet.y)
        guard simd_length(offset) > 1 else { return true }
        return abs(remainder(atan2(offset.y, offset.x) - yaw, 2 * Float.pi)) <= breathAim
    }
}
