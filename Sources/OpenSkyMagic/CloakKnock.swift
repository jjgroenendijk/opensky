// How hard a cloak's spell pushes the actors it lands on. Shield Charge's spell launches
// `VoicePushProjectile01`, whose impact force knocks enemies down
// (docs/engine/magic-archetypes.md#cloak-knock).

import Foundation

nonisolated public enum CloakKnock: Sendable {
    /// The push speed in units a second: the `PROJ` impact force times
    /// `fProjectileKnockMultBiped`, read as a Havok speed. Zero for no push.
    public static func speed(
        impactForce: Float,
        bipedMultiplier: Float,
        havokScale: Float
    ) -> Float {
        let speed = impactForce * bipedMultiplier * havokScale
        return speed.isFinite ? max(0, speed) : 0
    }
}
