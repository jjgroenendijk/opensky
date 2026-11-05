// The water rings bodies send out: a splash starts one, and an actor wading starts one
// each time it has moved a step. The water shader draws the newest few with the
// WATR displacement fields. Pure; see docs/rendering/water.md#displacement.

import Foundation
import OpenSkyFormatsESM
import simd

nonisolated public struct WaterRipple: Equatable, Sendable {
    public let position: SIMD2<Float>
    public let start: Float
    /// 0 to 1: a heavy splash is 1, a wading step less.
    public let strength: Float
}

nonisolated public struct WaterRippleField: Equatable, Sendable {
    /// The shader's ring count, `WaterConstantMaxRipples`.
    public static let limit = 8
    /// Seconds a ring lives; OpenSky's value.
    public static let lifetime: Float = 3
    /// Units an actor wades before it starts the next ring; OpenSky's value.
    public static let wakeSpacing: Float = 48
    public static let wakeStrength: Float = 0.4

    public private(set) var ripples: [WaterRipple] = []
    private var lastWake: [ReferenceKey: SIMD2<Float>] = [:]

    public init() {}

    public mutating func add(at position: SIMD3<Float>, strength: Float, time: Float) {
        guard position.x.isFinite, position.y.isFinite, time.isFinite else { return }
        ripples.append(WaterRipple(
            position: SIMD2(position.x, position.y), start: time,
            strength: strength.isFinite ? simd_clamp(strength, 0, 1) : 0
        ))
        if ripples.count > Self.limit {
            ripples.removeFirst(ripples.count - Self.limit)
        }
    }

    /// An actor or body in the water at `position`; starts a ring every `wakeSpacing`.
    public mutating func wade(_ key: ReferenceKey, at position: SIMD3<Float>, time: Float) {
        let flat = SIMD2(position.x, position.y)
        if let last = lastWake[key], simd_distance(last, flat) < Self.wakeSpacing {
            return
        }
        lastWake[key] = flat
        add(at: position, strength: Self.wakeStrength, time: time)
    }

    /// Forgets the waders not in `present`, so one that leaves and comes back starts a ring.
    public mutating func keepWaders(_ present: Set<ReferenceKey>) {
        lastWake = lastWake.filter { present.contains($0.key) }
    }

    /// Each live ring as x, y, age in seconds, strength; old rings drop out.
    public mutating func live(at time: Float) -> [SIMD4<Float>] {
        ripples.removeAll { time - $0.start > Self.lifetime || time < $0.start }
        return ripples.map { ripple in
            SIMD4<Float>(ripple.position.x, ripple.position.y, time - ripple.start, ripple.strength)
        }
    }
}
