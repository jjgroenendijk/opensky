// A living actor on the ground after a knock: down until its ragdoll lies still or the
// down time runs out, then getting up while the ragdoll pose blends back into the
// get-up clip. Values in, values out (docs/engine/ragdoll.md#knockdown).

import Foundation
public import OpenSkyFormatsESM
import simd

nonisolated public enum KnockdownPhase: Equatable, Sendable {
    /// On the ground, with the seconds left before it gets up anyway.
    case down(remaining: Float)
    /// Getting up: the ragdoll pose fades out over `duration` seconds.
    case gettingUp(elapsed: Float, duration: Float)
}

/// What one step of the knockdowns changed.
nonisolated public struct KnockdownStep: Equatable, Sendable {
    public var gettingUp: [ReferenceKey] = []
    public var stood: [ReferenceKey] = []
}

nonisolated public struct KnockdownTracker: Equatable, Sendable {
    public private(set) var phases: [ReferenceKey: KnockdownPhase] = [:]

    public init() {}

    public func isKnockedDown(_ key: ReferenceKey) -> Bool {
        phases[key] != nil
    }

    /// A new knock on an actor that is down or getting up puts it down again.
    public mutating func knockDown(_ key: ReferenceKey, downTime: Float) {
        phases[key] = .down(remaining: max(downTime.isFinite ? downTime : 0, 0))
    }

    public mutating func remove(_ key: ReferenceKey) {
        phases[key] = nil
    }

    /// Down actors get up once `isStill` or their time is out; getting-up actors stand once
    /// their blend of `getUpDuration` ends. Keys come back in ascending order.
    public mutating func advance(
        by delta: Float, getUpDuration: (ReferenceKey) -> Float, isStill: (ReferenceKey) -> Bool
    ) -> KnockdownStep {
        let delta = max(delta.isFinite ? delta : 0, 0)
        var step = KnockdownStep()
        for key in phases.keys.sorted() {
            switch phases[key] {
            case let .down(remaining):
                let left = remaining - delta
                if left <= 0 || isStill(key) {
                    phases[key] = .gettingUp(elapsed: 0, duration: max(getUpDuration(key), 0))
                    step.gettingUp.append(key)
                } else {
                    phases[key] = .down(remaining: left)
                }
            case let .gettingUp(elapsed, _):
                // The graph's get-up modifier runs only once the get-up has started.
                let duration = max(getUpDuration(key), 0)
                let now = elapsed + delta
                if now >= duration {
                    phases[key] = nil
                    step.stood.append(key)
                } else {
                    phases[key] = .gettingUp(elapsed: now, duration: duration)
                }
            case nil:
                continue
            }
        }
        return step
    }

    /// How much of the drawn pose the ragdoll owns: all of it while down, fading to none
    /// while getting up. Nil when the actor is not knocked down.
    public func ragdollWeight(of key: ReferenceKey) -> Float? {
        switch phases[key] {
        case .down: 1
        case let .gettingUp(elapsed, duration): duration > 0 ? max(0, 1 - elapsed / duration) : 0
        case nil: nil
        }
    }
}

nonisolated public enum KnockdownPush {
    /// The share of a knock's speed one body takes, by its bone: the torso and head all of
    /// it, upper limbs 0.75, lower limbs 0.5, hands and feet 0.25. Any other bone takes all.
    public static func weight(ofBone name: String) -> Float {
        let name = name.lowercased()
        if name.contains("hand") || name.contains("foot") {
            return 0.25
        }
        if name.contains("forearm") || name.contains("calf") {
            return 0.5
        }
        if name.contains("upperarm") || name.contains("thigh") || name.contains("clavicle") {
            return 0.75
        }
        return 1
    }

    /// The direction a knocked-down actor faces when it gets up: from its pelvis to its
    /// neck, along the ground, as a yaw counter-clockwise from +X.
    public static func getUpYaw(pelvis: SIMD3<Float>, neck: SIMD3<Float>) -> Float? {
        let along = SIMD2(neck.x - pelvis.x, neck.y - pelvis.y)
        guard simd_length_squared(along) > 1e-6 else { return nil }
        return atan2(along.y, along.x)
    }
}
