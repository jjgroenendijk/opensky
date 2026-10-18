// A push from outside the player's own movement: a trap's pushback or `PushActorAway`.

import simd

nonisolated extension WalkController {
    /// How fast a knockback fades on the ground, per second.
    static let knockbackDamping: Float = 4
    /// The fastest knockback, units per second, so a large script value cannot fling
    /// the capsule through a wall in one step.
    static let maximumKnockbackSpeed: Float = 1500

    /// Adds `velocity`, units per second. An upward part lifts the player off the ground.
    public mutating func knock(_ velocity: SIMD3<Float>) {
        guard velocity.x.isFinite, velocity.y.isFinite, velocity.z.isFinite else { return }
        var horizontal = knockback + SIMD2(velocity.x, velocity.y)
        let speed = simd_length(horizontal)
        if speed > Self.maximumKnockbackSpeed {
            horizontal *= Self.maximumKnockbackSpeed / speed
        }
        knockback = horizontal
        if velocity.z > 0 {
            verticalVelocity = max(verticalVelocity, min(velocity.z, Self.maximumKnockbackSpeed))
            isGrounded = false
            activeStepSupport = nil
        }
    }

    /// This step's knockback displacement. The knockback fades while grounded.
    mutating func knockbackStep(dt: Float) -> SIMD2<Float> {
        let displacement = knockback * dt
        if isGrounded {
            knockback *= max(0, 1 - Self.knockbackDamping * dt)
        }
        return displacement
    }
}
