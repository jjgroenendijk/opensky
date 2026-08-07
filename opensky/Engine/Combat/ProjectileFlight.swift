// How a launched projectile moves (issue #196, roadmap item 15.5, scope point
// 3).
//
// A pure function of numbers, deliberately: no world, no clock, no collision.
// That is what makes "a deterministic test pins spawn, apex and impact point"
// a plain arithmetic assertion, and it is why the impact query lives next door
// in `ProjectileImpact` instead of here.
//
// ## The integrator
//
// There is no drag, so the motion under a constant acceleration is exactly
//
//     p(t) = p₀ + v₀t + ½at²        v(t) = v₀ + at
//
// and the step below is that closed form applied over one `dt` rather than an
// approximation of it. Semi-implicit Euler — the integrator the dynamic-body
// solver uses — would accumulate a `½a·dt²` error per step against the same
// analytic curve, which is fine for a crate settling on a floor and is not fine
// for a trajectory the acceptance gate pins by its apex and impact point. So
// this is exact, and `apexHeight` and `drop(at:)` below can be checked against
// it in closed form rather than by re-running the loop.
//
// Substeps come from the caller. `ProjectileRuntime` advances on
// `WalkController.fixedTimeStep`, so a shot's trajectory is the same on a
// 60 Hz display as on a 120 Hz one — the requirement the issue words as
// "deterministic trajectories".
//
// ## `gravityFactor` is a multiplier, and that is a measurement
//
// PROJ's `gravity` member has no documented unit. `Projectile.swift` carries
// the measurement that settles it — over the 20 arrow-type PROJ records in
// `Skyrim.esm` the member is bounded by 1 while `speed` runs to the thousands,
// and the vanilla iron arrow drops 18.9 world units over 1,000 units of level
// flight on the multiplier reading against 0.0135 on the acceleration reading.
// UESP "Skyrim:Archery" describes the field only as "a gravity value, which
// determines how quickly the projectile drops (higher is faster)", which is
// consistent with the multiplier reading and rules out neither on its own; the
// data does the ruling out.
//
// The world gravity it multiplies is this engine's single gravity constant,
// `WalkController.gravity`. Sharing it rather than introducing a projectile
// gravity means an arrow and a dropped crate fall at rates that stay in step if
// the constant ever changes.
//
// Documented in docs/engine/archery.md.

import simd

/// Everything a projectile needs to know about the record that launched it.
///
/// A flattened, validated view of one `Projectile` rather than the record
/// itself: the runtime holds one of these per live projectile and must never
/// re-derive a number mid-flight, and every field here has already had its
/// non-finite and negative cases resolved.
nonisolated struct ProjectileProfile: Equatable, Sendable {
    /// The PROJ this came from, for the readout. Nil in a synthetic profile.
    let projectile: FormID?
    /// Launch speed, world units per second.
    let speed: Float
    /// PROJ `gravity`, a dimensionless multiplier over world gravity.
    let gravityFactor: Float
    /// PROJ `range`, world units. Zero means the record bounds nothing and only
    /// the caller's own cap applies.
    let range: Float
    /// PROJ `lifetime`, seconds. Zero means the record bounds nothing.
    let lifetime: Float
    /// PROJ `collisionRadius`, world units. The radius the impact sweep uses;
    /// zero flies as a point and is a supported case, not a degraded one.
    let collisionRadius: Float
    /// PROJ `impactForce`, carried for whatever pushes a dynamic body with it.
    let impactForce: Float
    /// PROJ flight SNDR; nil where the record names none.
    let sound: FormID?
    /// PROJ MODL, so a stuck arrow can be drawn from the same mesh that flew.
    let modelPath: String?

    init(
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
    init(record: Projectile) {
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
    var isFlyable: Bool {
        speed > 0
    }

    /// Non-finite and negative values become zero. A record that carries a NaN
    /// speed must produce a projectile that goes nowhere, never one whose
    /// position becomes NaN and poisons every query it touches.
    private static func clean(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }
}

/// Where a projectile is, right now.
nonisolated struct ProjectileFlightState: Equatable, Sendable {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    /// Path length travelled since launch, world units. This is what `range` is
    /// compared against, not the straight-line distance from the muzzle: an
    /// arrow lobbed in an arc has travelled further than it has displaced, and
    /// `range` bounds the flight rather than the reach.
    var travelled: Float = 0
    /// Seconds since launch, what `lifetime` is compared against.
    var age: Float = 0
}

nonisolated enum ProjectileFlight {
    /// Engine units per second squared. The same constant the player capsule
    /// and every dynamic body fall under.
    static let worldGravity = WalkController.gravity

    /// The downward acceleration this profile flies under, world units per
    /// second squared.
    static func acceleration(of profile: ProjectileProfile) -> SIMD3<Float> {
        SIMD3(0, 0, -worldGravity * profile.gravityFactor)
    }

    /// The state a shot starts in.
    ///
    /// - Parameters:
    ///   - origin: the muzzle, world space.
    ///   - direction: the aim ray. Normalized here, so an unnormalized vector
    ///     is accepted; a zero-length one launches along +X rather than
    ///     producing a NaN heading.
    ///   - profile: the PROJ's flight numbers.
    ///   - speedScale: what the launch speed is multiplied by, for a draw that
    ///     did not reach full. 1 is a full draw.
    static func launch(
        from origin: SIMD3<Float>,
        along direction: SIMD3<Float>,
        profile: ProjectileProfile,
        speedScale: Float = 1
    ) -> ProjectileFlightState {
        let scale = speedScale.isFinite ? max(0, speedScale) : 1
        return ProjectileFlightState(
            position: origin,
            velocity: normalized(direction) * profile.speed * scale
        )
    }

    /// One step of flight. Exact for the constant acceleration this model
    /// carries, so the result does not depend on how the caller subdivided the
    /// frame.
    static func step(
        _ state: ProjectileFlightState,
        profile: ProjectileProfile,
        dt: Float
    ) -> ProjectileFlightState {
        guard dt.isFinite, dt > 0 else { return state }
        let acceleration = acceleration(of: profile)
        let displacement = state.velocity * dt + acceleration * (0.5 * dt * dt)
        var next = state
        next.position = state.position + displacement
        next.velocity = state.velocity + acceleration * dt
        next.travelled = state.travelled + simd_length(displacement)
        next.age = state.age + dt
        return next
    }

    /// The greatest height a shot reaches above its launch point, world units.
    /// Zero for a level or descending shot. Closed form, for the readout and
    /// for the trajectory the acceptance test pins.
    static func apexHeight(of launch: ProjectileFlightState, profile: ProjectileProfile) -> Float {
        let acceleration = -acceleration(of: profile).z
        guard acceleration > 0, launch.velocity.z > 0 else { return 0 }
        return launch.velocity.z * launch.velocity.z / (2 * acceleration)
    }

    /// How far a shot has fallen below the straight line it was aimed along,
    /// after `time` seconds. Closed form: the whole of the deviation is the
    /// `½at²` term, because the launch velocity *is* the aim line.
    static func drop(of profile: ProjectileProfile, after time: Float) -> Float {
        guard time.isFinite, time > 0 else { return 0 }
        return 0.5 * worldGravity * profile.gravityFactor * time * time
    }

    /// The same, at a horizontal distance rather than at a time. Nil when the
    /// shot has no horizontal speed to cover the distance with.
    ///
    /// Reported against the horizontal component so that "drop at 1000 units"
    /// means what an archer means by it — how far below the reticle the arrow
    /// lands on a level shot — rather than how far it fell along its own arc.
    static func drop(
        of profile: ProjectileProfile,
        atHorizontalDistance distance: Float,
        launchDirection: SIMD3<Float>
    ) -> Float? {
        let direction = normalized(launchDirection)
        let horizontalSpeed = simd_length(SIMD2(direction.x, direction.y)) * profile.speed
        guard horizontalSpeed > 0, distance.isFinite, distance >= 0 else { return nil }
        return drop(of: profile, after: distance / horizontalSpeed)
    }

    /// A unit vector, with a documented answer for the degenerate input.
    static func normalized(_ direction: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(direction)
        guard length.isFinite, length > Float.ulpOfOne else { return SIMD3(1, 0, 0) }
        return direction / length
    }

    /// The aim ray for a shot: the camera's forward direction rotated up by
    /// `tiltDegrees` about the horizontal axis perpendicular to it.
    ///
    /// The tilt is a rotation of the whole ray rather than an addition to its
    /// pitch, so a shot aimed straight down is tilted by the same angle as one
    /// aimed level instead of wrapping past vertical.
    static func aimDirection(
        cameraForward: SIMD3<Float>,
        tiltDegrees: Float
    ) -> SIMD3<Float> {
        let forward = normalized(cameraForward)
        guard tiltDegrees.isFinite, tiltDegrees != 0 else { return forward }
        // The axis to pitch about is the horizontal right vector. A ray aimed
        // exactly along the world's up axis has none, and is left untilted:
        // there is no "up" left to tilt it toward.
        let right = simd_cross(forward, SIMD3<Float>(0, 0, 1))
        let length = simd_length(right)
        guard length > Float.ulpOfOne else { return forward }
        let rotation = simd_quatf(
            angle: tiltDegrees * Float.pi / 180, axis: right / length
        )
        return normalized(rotation.act(forward))
    }
}
