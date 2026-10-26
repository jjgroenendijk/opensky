// What the rider asks of a ridden dragon: lock a target, attack it, and land. The
// rider does not steer; the dragon circles (UESP "Skyrim:Dragon Riding"). Pure; the
// mount coordinator is the shell. See docs/engine/dragon-flight.md#riding.

import Foundation
import OpenSkyActorPresentation
import OpenSkyFormatsESM
import simd

/// The rider's orders and the ridden flight numbers. The radii, the breath range, and
/// the breath interval are OpenSky's: no setting names them.
nonisolated public struct RiddenDragonOrders: Equatable, Sendable {
    public static let circleRadius: Float = 3000
    public static let attackRadius: Float = 1500
    /// The farthest a ridden dragon breathes at its target from.
    public static let breathRange: Float = 3500
    public static let breathInterval: Float = 6

    public var landingRequested = false
    public var lockedTarget: ReferenceKey?
    public var isAttacking = false
    /// Where the dragon took off; it circles here without a target.
    public var home: SIMD3<Float>?
    public var breathCooldown: Float = 0
    /// The sneak toggle at the last step: a change is the attack key.
    public var lastSneak: Bool?

    public init() {}

    /// Lock target (the jump key): locks the target in view, or unlocks when there is
    /// none or it is the one already locked. Unlocking ends the attack.
    public mutating func lock(_ candidate: ReferenceKey?) {
        if candidate == nil || candidate == lockedTarget {
            lockedTarget = nil
            isAttacking = false
        } else {
            lockedTarget = candidate
        }
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

    /// Counts the breath cooldown down. True when the dragon breathes at its target now.
    public mutating func breathes(
        from feet: SIMD3<Float>, at target: SIMD3<Float>?, deltaTime: Float
    ) -> Bool {
        breathCooldown = max(0, breathCooldown - max(deltaTime, 0))
        guard
            isAttacking, let target, breathCooldown <= 0,
            simd_distance(feet, target) <= Self.breathRange
        else { return false }
        breathCooldown = Self.breathInterval
        return true
    }
}
