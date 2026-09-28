import OpenSkyFormatsESM
import simd

/// Everything a projectile needs to know about the record that launched it.
///
/// A flattened, validated view of one `Projectile` rather than the record
/// itself: the runtime holds one of these per live projectile and must never
/// re-derive a number mid-flight, and every field here has already had its
/// non-finite and negative cases resolved.
nonisolated public struct ProjectileProfile: Equatable, Sendable {
    /// The PROJ this came from, for the readout. Nil in a synthetic profile.
    public let projectile: FormID?
    /// Launch speed, world units per second.
    public let speed: Float
    /// PROJ `gravity`, a dimensionless multiplier over world gravity.
    public let gravityFactor: Float
    /// PROJ `range`, world units. Zero means the record bounds nothing and only
    /// the caller's own cap applies.
    public let range: Float
    /// PROJ `lifetime`, seconds. Zero means the record bounds nothing.
    public let lifetime: Float
    /// PROJ `collisionRadius`, world units. The radius the impact sweep uses;
    /// zero flies as a point and is a supported case, not a degraded one.
    public let collisionRadius: Float
    /// PROJ `impactForce`, carried for whatever pushes a dynamic body with it.
    public let impactForce: Float
    /// PROJ flight SNDR; nil where the record names none.
    public let sound: FormID?
    /// PROJ MODL, so a stuck arrow can be drawn from the same mesh that flew.
    public let modelPath: String?

    public init(
        projectile: FormID? = nil,
        speed: Float,
        gravityFactor: Float,
        range: Float = 0,
        lifetime: Float = 0,
        collisionRadius: Float = 0,
        impactForce: Float = 0,
        sound: FormID? = nil,
        modelPath: String? = nil
    ) {
        self.projectile = projectile
        self.speed = Self.clean(speed)
        self.gravityFactor = Self.clean(gravityFactor)
        self.range = Self.clean(range)
        self.lifetime = Self.clean(lifetime)
        self.collisionRadius = Self.clean(collisionRadius)
        self.impactForce = Self.clean(impactForce)
        self.sound = sound
        self.modelPath = modelPath
    }

    /// One decoded PROJ as a flight profile.
    public init(record: Projectile) {
        self.init(
            projectile: record.formID,
            speed: record.speed,
            gravityFactor: record.gravityFactor,
            range: record.range,
            lifetime: record.lifetime,
            collisionRadius: record.collisionRadius,
            impactForce: record.impactForce,
            sound: record.sound,
            modelPath: record.modelPath
        )
    }

    /// Whether this profile describes something the flight model can integrate.
    public var isFlyable: Bool {
        speed > 0
    }

    /// Non-finite and negative values become zero. A record that carries a NaN
    /// speed must produce a projectile that goes nowhere, never one whose
    /// position becomes NaN and poisons every query it touches.
    private static func clean(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }
}
