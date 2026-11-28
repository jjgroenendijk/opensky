public import OpenSkyFormatsESM
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
    public var gravityFactor: Float
    /// PROJ `range`, world units. Zero means the record bounds nothing and only
    /// the caller's own cap applies.
    public let range: Float
    /// PROJ `lifetime`, seconds. Zero means the record bounds nothing.
    public let lifetime: Float
    /// PROJ `collisionRadius`, world units. The radius the impact sweep uses;
    /// zero flies as a point and is a supported case, not a degraded one.
    public let collisionRadius: Float
    /// PROJ `explosion`, spelled in the item plugin. Nil on a projectile that does not explode.
    public var explosion: FormID?
    /// With the alternate trigger: an actor this close detonates it. Zero is off.
    public var explosionProximity: Float = 0
    /// With the alternate trigger: seconds of flight that detonate it. Zero is off.
    public var explosionTimer: Float = 0
    /// PROJ DATA impact force, in Havok units: how hard a hit pushes a loose body.
    public var impactForce: Float = 0
    /// A flame or cone PROJ: a spray that a wall stops through a look ahead, not a body.
    public var isCone = false
    /// PROJ DATA type, which the kill cam paths test; nil in a synthetic profile.
    public var kind: Projectile.Kind?
    /// What the player sees of it (docs/engine/spell-delivery.md#what-a-projectile-shows).
    public var visuals = ProjectileVisuals()
    /// What the explosion's radius is multiplied by: above 1 for a dual cast.
    public var explosionScale: Float = 1
    /// `DATA` flag 0x400 clear: an NPC's shot turns toward its combat aim point.
    public var correctsCombatAim = true
    /// What using the projectile does once it stands in the world.
    public var activation = ProjectileActivation()

    public init(
        projectile: FormID? = nil,
        speed: Float,
        gravityFactor: Float,
        range: Float = 0,
        lifetime: Float = 0,
        collisionRadius: Float = 0
    ) {
        self.projectile = projectile
        self.speed = Self.clean(speed)
        self.gravityFactor = Self.clean(gravityFactor)
        self.range = Self.clean(range)
        self.lifetime = Self.clean(lifetime)
        self.collisionRadius = Self.clean(collisionRadius)
    }

    /// One decoded PROJ as a flight profile.
    public init(record: Projectile) {
        self.init(
            projectile: record.formID,
            speed: record.speed,
            gravityFactor: record.gravityFactor,
            range: record.range,
            lifetime: record.lifetime,
            collisionRadius: record.collisionRadius
        )
        impactForce = Self.clean(record.impactForce)
        isCone = record.kind == .flame || record.kind == .cone
        kind = record.kind
        correctsCombatAim = !record.flags.contains(.disableCombatAimCorrection)
        activation = ProjectileActivation(record: record)
        visuals = ProjectileVisuals(record: record)
        // A trap dart names `FireBallExp01` but leaves the explosion flag off.
        explosion = record.flags.contains(.explosion) ? record.explosion : nil
        if record.flags.contains(.alternateTrigger) {
            explosionProximity = Self.clean(record.explosionProximity)
            explosionTimer = Self.clean(record.explosionTimer)
        }
    }

    /// The gravity factor an NPC's aim plans with: a lobber plans for full world gravity.
    public var aimGravityFactor: Float {
        kind == .lobber ? 1 : gravityFactor
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

/// The PROJ model, its light in flight, and its muzzle flash. Links are spelled in the
/// item plugin, as `ProjectileProfile.explosion` is.
nonisolated public struct ProjectileVisuals: Equatable, Sendable {
    /// MODL, drawn along the flight.
    public var model: String?
    public var light: FormID?
    /// NAM1, shown at the launch point; nil without the muzzle flash flag.
    public var muzzleFlashModel: String?
    public var muzzleFlashLight: FormID?
    /// Seconds the muzzle flash shows.
    public var muzzleFlashDuration: Float = 0
    /// The model's size: above 1 for a dual cast.
    public var scale: Float = 1

    public init() {}

    public init(record: Projectile) {
        model = Self.path(record.modelPath)
        light = record.light
        guard record.flags.contains(.muzzleFlash) else { return }
        muzzleFlashModel = Self.path(record.details.muzzleFlashModelPath)
        muzzleFlashLight = record.muzzleFlashLight
        let duration = record.muzzleFlashDuration
        muzzleFlashDuration = duration.isFinite ? max(duration, 0) : 0
    }

    /// Whether launching shows anything at the muzzle.
    public var hasMuzzleFlash: Bool {
        muzzleFlashDuration > 0 && muzzleFlashModel != nil
    }

    private static func path(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return path
    }
}

/// The `PROJ` flags Can Be Disabled and Can Be Picked Up, and the disable sound.
/// See docs/engine/projectiles.md, "Pick-up, bounce, and stick in the game".
nonisolated public struct ProjectileActivation: Equatable, Sendable {
    public var canBePickedUp: Bool
    public var canBeDisabled: Bool
    public var disableSound: FormID?

    /// A shot without a record, such as a dev shot, can be picked up.
    public init(
        canBePickedUp: Bool = true,
        canBeDisabled: Bool = false,
        disableSound: FormID? = nil
    ) {
        self.canBePickedUp = canBePickedUp
        self.canBeDisabled = canBeDisabled
        self.disableSound = disableSound
    }

    public init(record: Projectile) {
        self.init(
            canBePickedUp: record.flags.contains(.canBePickedUp),
            canBeDisabled: record.flags.contains(.canBeDisabled),
            disableSound: record.disableSound
        )
    }
}
