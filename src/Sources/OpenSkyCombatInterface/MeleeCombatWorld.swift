import OpenSkyBehavior
public import OpenSkyFormatsESM
public import OpenSkyPhysics
import simd

/// Who is swinging, and from where.
nonisolated public struct MeleeAttacker: Equatable, Sendable {
    /// The attacker's reference, so a swing can never hit its own owner.
    public let key: ReferenceKey
    /// Capsule bottom, world space.
    public let feet: SIMD3<Float>
    public let capsule: PlayerCapsule
    /// Facing yaw in radians, in the locomotion bridge's convention.
    public let facing: Float
    /// The actor's scale, which multiplies reach. 1 for the player, whose XSCL
    /// this engine does not read.
    public let scale: Float
    /// The race's unarmed reach before scale. Nil falls back to `fCombatDistance`.
    public let unarmedReach: Float?
    /// A kill camera plays, which multiplies the player's reach.
    public var inKillCamera = false

    public init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        capsule: PlayerCapsule = .standard,
        facing: Float,
        scale: Float = 1,
        unarmedReach: Float? = nil
    ) {
        self.key = key
        self.feet = feet
        self.capsule = capsule
        self.facing = facing
        self.scale = scale
        self.unarmedReach = unarmedReach
    }
}
